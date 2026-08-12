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

from builtin_interfaces.msg import Duration
from foxglove_msgs.msg import (
    ArrowPrimitive,
    Color,
    LinePrimitive,
    SceneEntity,
    SceneUpdate,
    SpherePrimitive,
    TextPrimitive,
)
from geometry_msgs.msg import Point, Pose, Quaternion, TwistStamped, Vector3
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from std_srvs.srv import SetBool
from vision_msgs.msg import Detection2DArray, Detection3DArray

STANDOFF_COLOR = Color(r=0.1, g=0.9, b=1.0, a=0.8)
VELOCITY_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
TARGET_COLOR = Color(r=1.0, g=0.5, b=0.0, a=0.35)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)

IDENTITY_ORIENTATION = Quaternion(x=0.0, y=0.0, z=0.0, w=1.0)
SCENE_LIFETIME = Duration(sec=0, nanosec=500000000)
TARGET_MARKER_DIAMETER_M = 0.15
RING_SEGMENTS = 48
LIVE_PARAMETERS = frozenset({
    'standoff_distance', 'distance_gain', 'max_forward_speed',
    'steer_gain', 'max_angular_speed', 'reacquire_frames',
    'target_class', 'command_smoothing', 'distance_deadband',
    'steer_deadband', 'distance_damping', 'steer_damping',
    'max_retreat_speed',
})
MAX_MEASUREMENT_INTERVAL_S = 0.2
TARGET_MATCH_RADIUS_M = 0.6
NEARER_TAKEOVER_MARGIN_M = 0.4


class Approach(Node):
    def __init__(self):
        super().__init__('approach')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        detections_3d_topic = self.declare_parameter(
            'detections_3d_topic', 'detections_3d'
        ).value
        self.target_class = self.declare_parameter('target_class', '').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        scene_topic = self.declare_parameter('scene_topic', 'perception/vision/scene').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.standoff_distance = self.declare_parameter('standoff_distance', 1.0).value
        self.distance_gain = self.declare_parameter('distance_gain', 0.6).value
        self.max_forward_speed = self.declare_parameter('max_forward_speed', 0.6).value
        self.steer_gain = self.declare_parameter('steer_gain', 1.2).value
        self.max_angular_speed = self.declare_parameter('max_angular_speed', 0.8).value
        self.reacquire_frames = self.declare_parameter('reacquire_frames', 0).value
        self.command_smoothing = self.declare_parameter('command_smoothing', 1.0).value
        self.distance_deadband = self.declare_parameter('distance_deadband', 0.0).value
        self.steer_deadband = self.declare_parameter('steer_deadband', 0.0).value
        self.distance_damping = self.declare_parameter('distance_damping', 0.0).value
        self.steer_damping = self.declare_parameter('steer_damping', 0.0).value
        self.max_retreat_speed = self.declare_parameter('max_retreat_speed', 0.0).value

        self.is_enabled = self.declare_parameter('start_enabled', False).value
        self.missing_frames = 0
        self.last_angular_speed = 0.0
        self.smoothed_forward_speed = 0.0
        self.smoothed_angular_speed = 0.0
        self.previous_stamp_s = None
        self.previous_offset = 0.0
        self.previous_distance = 0.0
        self.tracked_position = None
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, 10
        )
        self.scene_publisher = self.create_publisher(SceneUpdate, scene_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            Detection2DArray, detections_topic, self.on_detections, qos_profile_sensor_data
        )
        self.create_subscription(
            Detection3DArray, detections_3d_topic, self.on_detections,
            qos_profile_sensor_data
        )
        self.get_logger().info(f'approach: {detections_topic} -> {cmd_vel_topic}')

    def on_detections(self, message):
        target = self.select_target(self.candidate_points(message.detections))
        if target is None:
            self.missing_frames += 1
            if self.missing_frames > self.reacquire_frames:
                self.tracked_position = None
            angular_speed = (
                self.last_angular_speed
                if self.missing_frames <= self.reacquire_frames else 0.0
            )
            self.previous_stamp_s = None
            self.drive(0.0, angular_speed)
            self.publish_scene(message.header.stamp, message.header.frame_id, None, 0.0)
            return
        self.missing_frames = 0
        lateral_offset = target.x if abs(target.x) > self.steer_deadband else 0.0
        offset = lateral_offset / target.z
        stamp_s = message.header.stamp.sec + message.header.stamp.nanosec * 1e-9
        offset_rate = 0.0
        distance_rate = 0.0
        if (self.previous_stamp_s is not None
                and 0.0 < stamp_s - self.previous_stamp_s < MAX_MEASUREMENT_INTERVAL_S):
            interval = stamp_s - self.previous_stamp_s
            offset_rate = (offset - self.previous_offset) / interval
            distance_rate = (target.z - self.previous_distance) / interval
        self.previous_stamp_s = stamp_s
        self.previous_offset = offset
        self.previous_distance = target.z
        forward_speed = self.approach_speed(target.z, distance_rate)
        self.last_angular_speed = float(np.clip(
            -(self.steer_gain * offset + self.steer_damping * offset_rate),
            -self.max_angular_speed, self.max_angular_speed))
        self.drive(forward_speed, self.last_angular_speed)
        self.publish_scene(message.header.stamp, message.header.frame_id, target, forward_speed)

    def candidate_points(self, detections):
        points = []
        for detection in detections:
            if not detection.results:
                continue
            result = detection.results[0]
            if self.target_class and result.hypothesis.class_id != self.target_class:
                continue
            point = result.pose.pose.position
            if point.z <= 0.0:
                continue
            points.append(point)
        return points

    def select_target(self, candidates):
        if not candidates:
            return None
        nearest = min(candidates, key=lambda point: point.z)
        tracked = self.tracked_candidate(candidates)
        target = nearest
        if (tracked is not None
                and nearest.z > tracked.z - NEARER_TAKEOVER_MARGIN_M):
            target = tracked
        if target is not tracked:
            self.previous_stamp_s = None
        self.tracked_position = target
        return target

    def tracked_candidate(self, candidates):
        if self.tracked_position is None:
            return None
        closest = min(candidates, key=self.distance_to_tracked)
        if self.distance_to_tracked(closest) > TARGET_MATCH_RADIUS_M:
            return None
        return closest

    def distance_to_tracked(self, point):
        return math.hypot(
            point.x - self.tracked_position.x, point.z - self.tracked_position.z)

    def approach_speed(self, distance, distance_rate):
        error = distance - self.standoff_distance
        if abs(error) < self.distance_deadband:
            return 0.0
        return float(np.clip(
            self.distance_gain * error + self.distance_damping * distance_rate,
            -self.max_retreat_speed, self.max_forward_speed))

    def drive(self, forward_speed, angular_speed):
        if not self.is_enabled:
            return
        self.smoothed_forward_speed += self.command_smoothing * (
            forward_speed - self.smoothed_forward_speed)
        self.smoothed_angular_speed += self.command_smoothing * (
            angular_speed - self.smoothed_angular_speed)
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(self.smoothed_forward_speed)
        message.twist.angular.z = float(
            np.clip(
                self.smoothed_angular_speed,
                -self.max_angular_speed, self.max_angular_speed,
            )
        )
        self.cmd_vel_publisher.publish(message)

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)

    def publish_scene(self, stamp, target_frame_id, point, forward_speed):
        scene = SceneUpdate()
        scene.entities.append(self.standoff_entity(stamp))
        scene.entities.append(self.velocity_entity(stamp, forward_speed))
        if point is not None:
            scene.entities.append(self.target_entity(stamp, target_frame_id, point))
        self.scene_publisher.publish(scene)

    def target_entity(self, stamp, frame_id, point):
        entity = self.scene_entity(stamp, frame_id, 'target')
        sphere = SpherePrimitive()
        sphere.pose = Pose(position=point, orientation=IDENTITY_ORIENTATION)
        sphere.size = Vector3(
            x=TARGET_MARKER_DIAMETER_M, y=TARGET_MARKER_DIAMETER_M, z=TARGET_MARKER_DIAMETER_M)
        sphere.color = TARGET_COLOR
        entity.spheres.append(sphere)
        label = TextPrimitive()
        label.pose = Pose(position=point, orientation=IDENTITY_ORIENTATION)
        label.billboard = True
        label.font_size = 14.0
        label.scale_invariant = True
        label.color = TEXT_COLOR
        label.text = f'{point.z:.2f} m'
        entity.texts.append(label)
        return entity

    def standoff_entity(self, stamp):
        entity = self.scene_entity(stamp, self.frame_id, 'standoff')
        ring = LinePrimitive()
        ring.type = LinePrimitive.LINE_LOOP
        ring.pose = Pose(orientation=IDENTITY_ORIENTATION)
        ring.thickness = 0.03
        ring.color = STANDOFF_COLOR
        ring.points = [
            Point(
                x=self.standoff_distance * math.cos(2.0 * math.pi * index / RING_SEGMENTS),
                y=self.standoff_distance * math.sin(2.0 * math.pi * index / RING_SEGMENTS),
                z=0.0,
            )
            for index in range(RING_SEGMENTS)
        ]
        entity.lines.append(ring)
        return entity

    def velocity_entity(self, stamp, forward_speed):
        entity = self.scene_entity(stamp, self.frame_id, 'velocity')
        arrow = ArrowPrimitive()
        arrow.pose = Pose(orientation=IDENTITY_ORIENTATION)
        arrow.shaft_length = forward_speed
        arrow.shaft_diameter = 0.03
        arrow.head_length = 0.08
        arrow.head_diameter = 0.07
        arrow.color = VELOCITY_COLOR
        entity.arrows.append(arrow)
        return entity

    def scene_entity(self, stamp, frame_id, entity_id):
        entity = SceneEntity()
        entity.timestamp = stamp
        entity.frame_id = frame_id
        entity.id = entity_id
        entity.lifetime = SCENE_LIFETIME
        entity.frame_locked = True
        return entity


def main():
    rclpy.init()
    node = Approach()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.smoothed_forward_speed = 0.0
        node.smoothed_angular_speed = 0.0
        node.drive(0.0, 0.0)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
