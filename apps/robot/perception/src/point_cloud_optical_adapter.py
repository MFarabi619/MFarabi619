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


from geometry_msgs.msg import TransformStamped
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2
from tf2_sensor_msgs.tf2_sensor_msgs import do_transform_cloud


def body_to_optical_transform(optical_frame):
    transform = TransformStamped()
    transform.header.frame_id = optical_frame
    transform.transform.rotation.w = 0.5
    transform.transform.rotation.x = 0.5
    transform.transform.rotation.y = -0.5
    transform.transform.rotation.z = 0.5
    return transform


class PointCloudOpticalAdapter(Node):
    def __init__(self):
        super().__init__('point_cloud_optical_adapter')
        body_point_cloud_topic = self.declare_parameter(
            'body_point_cloud_topic', '/sensors/camera_0/depth/points_body').value
        optical_point_cloud_topic = self.declare_parameter(
            'optical_point_cloud_topic', '/sensors/camera_0/depth/points').value
        optical_frame = self.declare_parameter(
            'optical_frame', 'camera_0_color_optical_frame').value

        self.body_to_optical = body_to_optical_transform(optical_frame)
        self.optical_point_cloud_publisher = self.create_publisher(
            PointCloud2, optical_point_cloud_topic, qos_profile_sensor_data)
        self.create_subscription(
            PointCloud2, body_point_cloud_topic, self.on_point_cloud,
            qos_profile_sensor_data)
        self.get_logger().info(
            'point cloud optical adapter: '
            f'{body_point_cloud_topic} -> {optical_point_cloud_topic}')

    def on_point_cloud(self, message):
        optical_point_cloud = do_transform_cloud(message, self.body_to_optical)
        optical_point_cloud.header.stamp = message.header.stamp
        self.optical_point_cloud_publisher.publish(optical_point_cloud)


def main():
    rclpy.init()
    node = PointCloudOpticalAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
