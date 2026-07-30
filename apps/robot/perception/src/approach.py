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
from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from std_srvs.srv import SetBool
from vision_msgs.msg import Detection2DArray

STANDOFF_COLOR = Color(r=0.1, g=0.9, b=1.0, a=0.8)
VELOCITY_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
CONE_COLOR = Color(r=1.0, g=0.5, b=0.0, a=0.35)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)

IDENTITY_ORIENTATION = Quaternion(x=0.0, y=0.0, z=0.0, w=1.0)
SCENE_LIFETIME = Duration(sec=0, nanosec=500000000)
CONE_MARKER_DIAMETER = 0.15
RING_SEGMENTS = 48
LIVE_PARAMETERS = frozenset({
    'standoff_distance', 'distance_gain', 'max_forward_speed',
    'steer_gain', 'max_angular_speed',
})


class Approach(Node):
    def __init__(self):
        super().__init__('approach')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        scene_topic = self.declare_parameter('scene_topic', 'perception/vision/scene').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.standoff_distance = self.declare_parameter('standoff_distance', 1.0).value
        self.distance_gain = self.declare_parameter('distance_gain', 0.6).value
        self.max_forward_speed = self.declare_parameter('max_forward_speed', 0.6).value
        self.steer_gain = self.declare_parameter('steer_gain', 1.2).value
        self.max_angular_speed = self.declare_parameter('max_angular_speed', 0.8).value

        self.enabled = False
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, qos_profile_sensor_data
        )
        self.scene_publisher = self.create_publisher(SceneUpdate, scene_topic, 10)
        self.add_on_set_parameters_callback(self.on_set_parameters)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            Detection2DArray, detections_topic, self.on_detections, qos_profile_sensor_data
        )
        self.get_logger().info(f'approach: {detections_topic} -> {cmd_vel_topic}')

    def on_detections(self, message):
        cone = self.nearest_cone(message.detections)
        if cone is None:
            self.drive(0.0, 0.0)
            self.publish_scene(message.header.stamp, message.header.frame_id, None, 0.0)
            return
        forward_speed = self.approach_speed(cone.z)
        self.drive(forward_speed, -self.steer_gain * cone.x / cone.z)
        self.publish_scene(message.header.stamp, message.header.frame_id, cone, forward_speed)

    def nearest_cone(self, detections):
        nearest = None
        for detection in detections:
            if not detection.results:
                continue
            point = detection.results[0].pose.pose.position
            if point.z <= 0.0:
                continue
            if nearest is None or point.z < nearest.z:
                nearest = point
        return nearest

    def approach_speed(self, distance):
        error = distance - self.standoff_distance
        return float(np.clip(self.distance_gain * error, 0.0, self.max_forward_speed))

    def drive(self, forward_speed, angular_speed):
        if not self.enabled:
            return
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(forward_speed)
        message.twist.angular.z = float(
            np.clip(angular_speed, -self.max_angular_speed, self.max_angular_speed)
        )
        self.cmd_vel_publisher.publish(message)

    def on_enable(self, request, response):
        self.enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_set_parameters(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)
        return SetParametersResult(successful=True)

    def publish_scene(self, stamp, cone_frame_id, point, forward_speed):
        scene = SceneUpdate()
        scene.entities.append(self.standoff_entity(stamp))
        scene.entities.append(self.velocity_entity(stamp, forward_speed))
        if point is not None:
            scene.entities.append(self.cone_entity(stamp, cone_frame_id, point))
        self.scene_publisher.publish(scene)

    def cone_entity(self, stamp, frame_id, point):
        entity = self.scene_entity(stamp, frame_id, 'cone')
        sphere = SpherePrimitive()
        sphere.pose = Pose(position=point, orientation=IDENTITY_ORIENTATION)
        sphere.size = Vector3(
            x=CONE_MARKER_DIAMETER, y=CONE_MARKER_DIAMETER, z=CONE_MARKER_DIAMETER)
        sphere.color = CONE_COLOR
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
        node.drive(0.0, 0.0)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
