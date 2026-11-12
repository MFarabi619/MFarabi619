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


import json
import math

from builtin_interfaces.msg import Duration
from foxglove_msgs.msg import (
    ArrowPrimitive,
    Color,
    GeoJSON,
    SceneEntity,
    SceneUpdate,
    TextPrimitive,
)
from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.node import Node
from rclpy.qos import (
    DurabilityPolicy,
    qos_profile_sensor_data,
    QoSProfile,
)
from sensor_msgs.msg import NavSatFix, NavSatStatus

TRACK_MIN_STEP_METERS = 1.0
TRACK_MAX_POINTS = 5000
METERS_PER_DEGREE_LATITUDE = 111_320.0
MOTION_EPSILON = 0.01

ARROW_COLOR = Color(r=0.2, g=1.0, b=0.4, a=0.9)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
LABEL_FONT_SIZE_PIXELS = 14.0
ARROW_SHAFT_DIAMETER_METERS = 0.05
ARROW_HEAD_LENGTH_METERS = 0.2
ARROW_HEAD_DIAMETER_METERS = 0.15
SCENE_LIFETIME_SECONDS = 0.5
NANOSECONDS_PER_SECOND = 1_000_000_000


def track_geojson(coordinates):
    return json.dumps({
        'type': 'FeatureCollection',
        'features': [{
            'type': 'Feature',
            'geometry': {'type': 'LineString', 'coordinates': coordinates},
            'properties': {'name': 'track'},
        }],
    })


class FoxglovePanels(Node):
    def __init__(self):
        super().__init__('foxglove_panels')
        self.track = []
        latched = QoSProfile(
            depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self.track_publisher = self.create_publisher(
            GeoJSON, 'visualization/track', latched)
        self.scene_publisher = self.create_publisher(
            SceneUpdate, 'visualization/scene', 10)
        self.create_subscription(
            NavSatFix, '/sensors/gps_0/fix', self.on_fix,
            qos_profile_sensor_data)
        self.create_subscription(
            TwistStamped, '/platform/cmd_vel', self.on_cmd_vel,
            qos_profile_sensor_data)

    def on_fix(self, message):
        if message.status.status == NavSatStatus.STATUS_NO_FIX:
            return
        if self.track:
            last_longitude, last_latitude = self.track[-1]
            meters_east = (
                (message.longitude - last_longitude)
                * METERS_PER_DEGREE_LATITUDE
                * math.cos(math.radians(message.latitude)))
            meters_north = (
                (message.latitude - last_latitude)
                * METERS_PER_DEGREE_LATITUDE)
            if math.hypot(meters_east, meters_north) < TRACK_MIN_STEP_METERS:
                return
        self.track.append([message.longitude, message.latitude])
        del self.track[:-TRACK_MAX_POINTS]
        self.track_publisher.publish(GeoJSON(geojson=track_geojson(self.track)))

    def on_cmd_vel(self, message):
        forward_speed_meters_per_second = message.twist.linear.x
        angular_speed_radians_per_second = message.twist.angular.z
        yaw = (
            angular_speed_radians_per_second
            if forward_speed_meters_per_second >= 0.0
            else angular_speed_radians_per_second + math.pi)

        entity = SceneEntity()
        entity.timestamp = self.get_clock().now().to_msg()
        entity.frame_id = 'base_link'
        entity.id = 'cmd_vel'
        entity.lifetime = Duration(
            sec=0, nanosec=int(SCENE_LIFETIME_SECONDS * NANOSECONDS_PER_SECOND))
        entity.frame_locked = True

        arrow = ArrowPrimitive()
        arrow.pose.position.z = 0.1
        arrow.pose.orientation.z = math.sin(yaw / 2.0)
        arrow.pose.orientation.w = math.cos(yaw / 2.0)
        arrow.shaft_length = abs(forward_speed_meters_per_second)
        arrow.shaft_diameter = ARROW_SHAFT_DIAMETER_METERS
        arrow.head_length = ARROW_HEAD_LENGTH_METERS
        arrow.head_diameter = ARROW_HEAD_DIAMETER_METERS
        arrow.color = ARROW_COLOR

        label = TextPrimitive()
        label.pose.position.z = 1.0
        label.billboard = True
        label.font_size = LABEL_FONT_SIZE_PIXELS
        label.scale_invariant = True
        label.color = TEXT_COLOR
        label.text = (
            f'{forward_speed_meters_per_second:+.1f} m/s'
            f'  {angular_speed_radians_per_second:+.1f} rad/s')

        if (abs(forward_speed_meters_per_second) > MOTION_EPSILON
                or abs(angular_speed_radians_per_second) > MOTION_EPSILON):
            entity.arrows = [arrow]
            entity.texts = [label]
        self.scene_publisher.publish(SceneUpdate(entities=[entity]))


def main():
    rclpy.init()
    rclpy.spin(FoxglovePanels())


if __name__ == '__main__':
    main()
