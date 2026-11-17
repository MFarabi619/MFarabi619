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


import cv2
from cv_bridge import CvBridge, cvtColorForDisplay
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image


class DepthView(Node):
    def __init__(self):
        super().__init__('depth_view')
        self.min_depth_meters = self.declare_parameter('min_depth_meters', 0.3).value
        self.max_depth_meters = self.declare_parameter('max_depth_meters', 20.0).value
        self.bridge = CvBridge()
        self.view_publisher = self.create_publisher(
            Image, 'depth/image_view', qos_profile_sensor_data)
        self.create_subscription(
            Image, 'depth/image_raw', self.on_depth, qos_profile_sensor_data)

    def on_depth(self, depth_message):
        depth_meters = self.bridge.imgmsg_to_cv2(depth_message)
        # Turbo runs blue to red; nearness puts near objects in red like the ZED SDK's
        # sl::VIEW::DEPTH, and NaN renders black for out-of-range pixels such as the sky.
        nearness_meters = np.where(
            np.isfinite(depth_meters), self.max_depth_meters - depth_meters, np.nan)
        view = cvtColorForDisplay(
            nearness_meters, '32FC1', 'bgr8', False,
            0.0, self.max_depth_meters - self.min_depth_meters, cv2.COLORMAP_TURBO)
        view_message = self.bridge.cv2_to_imgmsg(
            view, encoding='bgr8', header=depth_message.header)
        self.view_publisher.publish(view_message)


def main():
    rclpy.init()
    node = DepthView()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
