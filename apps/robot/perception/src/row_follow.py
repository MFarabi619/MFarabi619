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


from geometry_msgs.msg import TwistStamped
import numpy as np
from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from vision_msgs.msg import Detection2DArray

FOLLOW = 'follow'
TURN = 'turn'
SPEED_FALLOFF = 0.5
LIVE_PARAMETERS = frozenset({
    'target_offset', 'forward_speed', 'steer_gain', 'max_angular_speed',
    'turn_speed', 'end_of_row_frames', 'reacquire_offset',
})


class RowFollow(Node):
    def __init__(self):
        super().__init__('row_follow')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.image_width = self.declare_parameter('image_width', 1280).value
        self.target_offset = self.declare_parameter('target_offset', 0.0).value
        self.forward_speed = self.declare_parameter('forward_speed', 0.4).value
        self.steer_gain = self.declare_parameter('steer_gain', 1.2).value
        self.max_angular_speed = self.declare_parameter('max_angular_speed', 0.8).value
        self.turn_speed = self.declare_parameter('turn_speed', 0.6).value
        self.end_of_row_frames = self.declare_parameter('end_of_row_frames', 8).value
        self.reacquire_offset = self.declare_parameter('reacquire_offset', 0.35).value

        self.state = FOLLOW
        self.missing_frames = 0

        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, qos_profile_sensor_data
        )
        self.add_on_set_parameters_callback(self.on_set_parameters)
        self.create_subscription(
            Detection2DArray, detections_topic, self.on_detections, qos_profile_sensor_data
        )
        self.get_logger().info(f'row follow: {detections_topic} -> {cmd_vel_topic}')

    def on_detections(self, message):
        error = self.center_error(message.detections)
        if error is None:
            self.missing_frames += 1
            if self.missing_frames >= self.end_of_row_frames:
                self.state = TURN
        else:
            self.missing_frames = 0
            if self.state == TURN and abs(error) <= self.reacquire_offset:
                self.state = FOLLOW

        if error is not None and self.state == FOLLOW:
            self.drive(
                self.forward_speed * (1.0 - SPEED_FALLOFF * abs(error)),
                -self.steer_gain * error,
            )
        else:
            self.drive(0.0, self.turn_speed)

    def center_error(self, detections):
        half_width = self.image_width / 2.0
        offsets = [
            (detection.bbox.center.position.x - half_width) / half_width
            for detection in detections
        ]
        if not offsets:
            return None
        return min(offsets, key=abs) - self.target_offset

    def drive(self, forward_speed, angular_speed):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(forward_speed)
        message.twist.angular.z = float(
            np.clip(angular_speed, -self.max_angular_speed, self.max_angular_speed)
        )
        self.cmd_vel_publisher.publish(message)

    def on_set_parameters(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)
        return SetParametersResult(successful=True)


def main():
    rclpy.init()
    node = RowFollow()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.drive(0.0, 0.0)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
