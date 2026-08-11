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
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from std_msgs.msg import Float32

JPEG_QUALITY = 80


class CanopyDetector(Node):
    def __init__(self):
        super().__init__('canopy_detector')
        image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed').value
        mask_topic = self.declare_parameter(
            'mask_topic', 'perception/canopy/mask/compressed').value
        fraction_topic = self.declare_parameter(
            'fraction_topic', 'perception/canopy/fraction').value
        self.red_green_ratio_max = self.declare_parameter(
            'red_green_ratio_max', 0.95).value
        self.blue_green_ratio_max = self.declare_parameter(
            'blue_green_ratio_max', 0.95).value
        self.excess_green_min = self.declare_parameter('excess_green_min', 20.0).value

        self.mask_publisher = self.create_publisher(
            CompressedImage, mask_topic, qos_profile_sensor_data)
        self.fraction_publisher = self.create_publisher(Float32, fraction_topic, 10)
        self.create_subscription(
            CompressedImage, image_topic, self.on_image, qos_profile_sensor_data)
        self.get_logger().info(f'canopy detector: {image_topic} -> {mask_topic}')

    def on_image(self, message):
        image = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            return
        blue, green, red = cv2.split(image.astype(np.float32))
        is_green = (
            (green > 0.0)
            & (red < self.red_green_ratio_max * green)
            & (blue < self.blue_green_ratio_max * green)
            & (2.0 * green - red - blue > self.excess_green_min)
        )
        mask = np.where(is_green, 255, 0).astype(np.uint8)
        encoded, buffer = cv2.imencode(
            '.jpg', mask, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        if not encoded:
            return
        mask_message = CompressedImage()
        mask_message.header = message.header
        mask_message.format = 'jpeg'
        mask_message.data = buffer.tobytes()
        self.mask_publisher.publish(mask_message)
        self.fraction_publisher.publish(Float32(data=float(is_green.mean())))


def main():
    rclpy.init()
    node = CanopyDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
