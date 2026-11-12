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

from geometry_msgs.msg import PoseStamped, TwistStamped
from nav_msgs.msg import Path
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import LaserScan

LIVE_PARAMETERS = frozenset({
    'min_range_meters', 'max_range_meters', 'corridor_half_width_meters',
    'min_wall_points', 'default_half_width_meters', 'lookahead_distance_meters',
    'path_step_meters', 'forward_speed_meters_per_second', 'lateral_gain',
    'heading_gain', 'max_angular_speed_radians_per_second', 'drive_enabled',
})


class Wall:
    def __init__(self, slope, intercept):
        self.slope = slope
        self.intercept = intercept

    def y_at(self, x):
        return self.slope * x + self.intercept


class RowNavigator(Node):
    def __init__(self):
        super().__init__('row_navigator')
        scan_topic = self.declare_parameter('scan_topic', 'scan').value
        path_topic = self.declare_parameter('path_topic', 'path').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.min_range_meters = self.declare_parameter('min_range_meters', 0.3).value
        self.max_range_meters = self.declare_parameter('max_range_meters', 4.0).value
        self.corridor_half_width_meters = self.declare_parameter(
            'corridor_half_width_meters', 1.5).value
        self.min_wall_points = self.declare_parameter('min_wall_points', 6).value
        self.default_half_width_meters = self.declare_parameter(
            'default_half_width_meters', 0.5).value
        self.lookahead_distance_meters = self.declare_parameter(
            'lookahead_distance_meters', 2.5).value
        self.path_step_meters = self.declare_parameter('path_step_meters', 0.25).value
        self.forward_speed_meters_per_second = self.declare_parameter(
            'forward_speed_meters_per_second', 0.4).value
        self.lateral_gain = self.declare_parameter('lateral_gain', 0.8).value
        self.heading_gain = self.declare_parameter('heading_gain', 0.6).value
        self.max_angular_speed_radians_per_second = self.declare_parameter(
            'max_angular_speed_radians_per_second', 0.8).value
        self.drive_enabled = self.declare_parameter('drive_enabled', False).value

        self.path_publisher = self.create_publisher(
            Path, path_topic, qos_profile_sensor_data)
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            LaserScan, scan_topic, self.on_scan, qos_profile_sensor_data)
        self.get_logger().info(f'row navigator: {scan_topic} -> {path_topic}')

    def on_scan(self, message):
        x, y = self.scan_points(message)
        left = self.fit_wall(x[y > 0.0], y[y > 0.0])
        right = self.fit_wall(x[y < 0.0], y[y < 0.0])
        centerline = self.centerline(left, right)
        if centerline is None:
            self.get_logger().info(
                f'no corridor: {x.size} scan points in band',
                throttle_duration_sec=5.0)
            self.path_publisher.publish(self.empty_path(message.header.stamp))
            return
        self.path_publisher.publish(self.path(message.header.stamp, centerline))
        if self.drive_enabled:
            self.drive(self.forward_speed_meters_per_second, self.steering(centerline))

    def scan_points(self, message):
        ranges = np.asarray(message.ranges)
        angles = message.angle_min + np.arange(ranges.size) * message.angle_increment
        valid = (
            np.isfinite(ranges)
            & (ranges >= max(self.min_range_meters, message.range_min))
            & (ranges <= min(self.max_range_meters, message.range_max))
        )
        ranges = ranges[valid]
        angles = angles[valid]
        x = ranges * np.cos(angles)
        y = ranges * np.sin(angles)
        near = np.abs(y) <= self.corridor_half_width_meters
        return x[near], y[near]

    def fit_wall(self, x, y):
        if x.size < self.min_wall_points:
            return None
        slope, intercept = np.polyfit(x, y, 1)
        residuals = y - (slope * x + intercept)
        spread = residuals.std()
        if spread > 0.0:
            keep = np.abs(residuals) <= 2.0 * spread
            if keep.sum() >= self.min_wall_points:
                slope, intercept = np.polyfit(x[keep], y[keep], 1)
        return Wall(float(slope), float(intercept))

    def centerline(self, left, right):
        if left is not None and right is not None:
            return Wall(
                (left.slope + right.slope) / 2.0,
                (left.intercept + right.intercept) / 2.0)
        if left is not None:
            return Wall(left.slope, left.intercept - self.default_half_width_meters)
        if right is not None:
            return Wall(right.slope, right.intercept + self.default_half_width_meters)
        return None

    def path(self, stamp, centerline):
        message = Path()
        message.header.stamp = stamp
        message.header.frame_id = self.frame_id
        yaw = math.atan(centerline.slope)
        steps = max(int(self.lookahead_distance_meters / self.path_step_meters), 1)
        for index in range(steps + 1):
            x = index * self.path_step_meters
            pose = PoseStamped()
            pose.header = message.header
            pose.pose.position.x = x
            pose.pose.position.y = centerline.y_at(x)
            pose.pose.orientation.z = math.sin(yaw / 2.0)
            pose.pose.orientation.w = math.cos(yaw / 2.0)
            message.poses.append(pose)
        return message

    def empty_path(self, stamp):
        message = Path()
        message.header.stamp = stamp
        message.header.frame_id = self.frame_id
        return message

    def steering(self, centerline):
        lateral = centerline.intercept
        heading_radians = math.atan(centerline.slope)
        angular = self.lateral_gain * lateral + self.heading_gain * heading_radians
        return float(np.clip(
            angular,
            -self.max_angular_speed_radians_per_second,
            self.max_angular_speed_radians_per_second))

    def drive(self, forward_speed_meters_per_second, angular_speed_radians_per_second):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(forward_speed_meters_per_second)
        message.twist.angular.z = float(angular_speed_radians_per_second)
        self.cmd_vel_publisher.publish(message)

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)


def main():
    rclpy.init()
    node = RowNavigator()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
