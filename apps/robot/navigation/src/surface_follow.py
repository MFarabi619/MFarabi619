#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


import math
from typing import NamedTuple

from geometry_msgs.msg import TwistStamped
import numpy as np
from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.duration import Duration
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo
from std_srvs.srv import SetBool
from vision_msgs.msg import Detection2DArray

SPEED_FALLOFF = 0.5
CAMERA_INFO_WARNING_INTERVAL_SECONDS = 5.0
CONTROL_PERIOD_SECONDS = 0.05
MIN_SURFACE_TIMEOUT_SECONDS = 0.1
LIVE_PARAMETERS = frozenset({
    'lateral_offset_meters', 'camera_height_meters', 'forward_speed_meters_per_second',
    'steer_gain', 'max_angular_speed_radians_per_second', 'surface_timeout_seconds',
})
FIXED_PARAMETERS = frozenset({
    'detections_topic', 'camera_info_topic', 'cmd_vel_topic', 'frame_id',
    'start_enabled',
})


def finite_or(value, fallback):
    return value if math.isfinite(value) else fallback


class TwistCommand(NamedTuple):
    forward_speed_meters_per_second: float
    angular_speed_radians_per_second: float


class SurfaceFollow(Node):
    def __init__(self):
        super().__init__('surface_follow')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        camera_info_topic = self.declare_parameter(
            'camera_info_topic', 'sensors/camera_0/color/camera_info').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.lateral_offset_meters = self.declare_parameter('lateral_offset_meters', 0.0).value
        self.camera_height_meters = self.declare_parameter('camera_height_meters', 0.36).value
        self.forward_speed_meters_per_second = self.declare_parameter(
            'forward_speed_meters_per_second', 0.4).value
        self.steer_gain = self.declare_parameter('steer_gain', 1.2).value
        self.max_angular_speed_radians_per_second = self.declare_parameter(
            'max_angular_speed_radians_per_second', 0.8).value
        self.surface_timeout_seconds = self.declare_parameter(
            'surface_timeout_seconds', 2.0).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.image_width_pixels = None
        self.focal_length_x = None
        self.focal_length_y = None
        self.principal_point_y = None
        self.latest_command = None
        self.latest_surface_time = None

        self.cmd_vel_publisher = self.create_publisher(TwistStamped, cmd_vel_topic, 10)
        self.create_timer(CONTROL_PERIOD_SECONDS, self.on_control_period)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.add_on_set_parameters_callback(self.validate_parameters)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CameraInfo, camera_info_topic, self.on_camera_info, qos_profile_sensor_data
        )
        self.create_subscription(
            Detection2DArray, detections_topic, self.on_detections, qos_profile_sensor_data
        )
        self.get_logger().info(f'surface follow: {detections_topic} -> {cmd_vel_topic}')

    def on_camera_info(self, message):
        if message.width > 0:
            self.image_width_pixels = message.width
        if message.k[0] > 0.0 and message.k[4] > 0.0:
            self.focal_length_x = message.k[0]
            self.focal_length_y = message.k[4]
            self.principal_point_y = message.k[5]

    def on_detections(self, message):
        if not self.is_enabled:
            return
        if self.image_width_pixels is None:
            self.get_logger().warning(
                'waiting for camera info before steering',
                throttle_duration_sec=CAMERA_INFO_WARNING_INTERVAL_SECONDS)
            return
        error = self.center_error(message.detections)
        if error is None:
            self.latest_command = TwistCommand(self.coasting_speed(), 0.0)
            return
        self.latest_surface_time = self.get_clock().now()
        self.latest_command = TwistCommand(
            self.forward_speed_meters_per_second * (1.0 - SPEED_FALLOFF * abs(error)),
            -self.steer_gain * error,
        )

    def coasting_speed(self):
        if self.latest_command is None:
            return 0.0
        return self.latest_command.forward_speed_meters_per_second

    def on_control_period(self):
        if not self.is_enabled or self.latest_command is None:
            return
        if self.surface_is_stale():
            self.halt()
            return
        self.drive(
            self.latest_command.forward_speed_meters_per_second,
            self.latest_command.angular_speed_radians_per_second)

    def surface_is_stale(self):
        if self.latest_surface_time is None:
            return True
        timeout = Duration(seconds=max(
            finite_or(self.surface_timeout_seconds, MIN_SURFACE_TIMEOUT_SECONDS),
            MIN_SURFACE_TIMEOUT_SECONDS))
        return self.get_clock().now() - self.latest_surface_time > timeout

    def center_error(self, detections):
        half_width = self.image_width_pixels / 2.0
        candidates = [
            ((detection.bbox.center.position.x - half_width) / half_width,
             self.target_offset(detection.bbox.center.position.y),
             detection.bbox.size_x / 2.0 / half_width)
            for detection in detections
        ]
        if not candidates:
            return None
        underfoot = [
            candidate for candidate in candidates if abs(candidate[0]) <= candidate[2]
        ]
        offset, target, _ = min(
            underfoot or candidates, key=lambda candidate: abs(candidate[0]))
        return offset - target

    def target_offset(self, row):
        lateral_offset_meters = finite_or(self.lateral_offset_meters, 0.0)
        camera_height_meters = finite_or(self.camera_height_meters, 0.0)
        if lateral_offset_meters == 0.0 or camera_height_meters <= 0.0:
            return 0.0
        if self.focal_length_x is None:
            return 0.0
        rows_below_horizon = row - self.principal_point_y
        if rows_below_horizon <= 0.0:
            return 0.0
        ground_range_meters = camera_height_meters * self.focal_length_y / rows_below_horizon
        pixels = -lateral_offset_meters * self.focal_length_x / ground_range_meters
        return pixels / (self.image_width_pixels / 2.0)

    def halt(self):
        self.publish_twist(0.0, 0.0)

    def drive(self, forward_speed_meters_per_second, angular_speed_radians_per_second):
        max_forward_speed_meters_per_second = max(
            finite_or(self.forward_speed_meters_per_second, 0.0), 0.0)
        max_angular_speed_radians_per_second = abs(
            finite_or(self.max_angular_speed_radians_per_second, 0.0))
        self.publish_twist(
            float(np.clip(
                finite_or(forward_speed_meters_per_second, 0.0),
                0.0, max_forward_speed_meters_per_second)),
            float(np.clip(
                finite_or(angular_speed_radians_per_second, 0.0),
                -max_angular_speed_radians_per_second, max_angular_speed_radians_per_second)),
        )

    def publish_twist(self, forward_speed_meters_per_second, angular_speed_radians_per_second):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = forward_speed_meters_per_second
        message.twist.angular.z = angular_speed_radians_per_second
        self.cmd_vel_publisher.publish(message)

    def on_enable(self, request, response):
        self.is_enabled = request.data
        self.latest_command = None
        self.latest_surface_time = None
        if not request.data:
            self.halt()
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def validate_parameters(self, parameters):
        for parameter in parameters:
            if parameter.name in FIXED_PARAMETERS:
                return SetParametersResult(
                    successful=False,
                    reason=f'{parameter.name} is fixed at launch')
            if parameter.name not in LIVE_PARAMETERS:
                continue
            if not math.isfinite(parameter.value):
                return SetParametersResult(
                    successful=False,
                    reason=f'{parameter.name} must be a finite number')
            if parameter.name == 'camera_height_meters' and parameter.value <= 0.0:
                return SetParametersResult(
                    successful=False, reason='camera_height_meters must be positive')
        return SetParametersResult(successful=True)

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)


def main():
    rclpy.init()
    node = SurfaceFollow()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        if rclpy.ok():
            node.halt()
            rclpy.shutdown()
        node.destroy_node()


if __name__ == '__main__':
    main()
