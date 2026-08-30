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
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage


class UsbWebcam(Node):
    def __init__(self, **node_arguments):
        super().__init__('usb_webcam', **node_arguments)
        image_topic = self.declare_parameter('image_topic', '/image').value
        device_index = self.declare_parameter('device_index', 0).value
        frames_per_second = self.declare_parameter(
            'frames_per_second', 15.0).value
        self.jpeg_quality = self.declare_parameter('jpeg_quality', 80).value
        self.frame_id = self.declare_parameter('frame_id', 'webcam').value

        self.camera = cv2.VideoCapture(device_index)
        self.image_publisher = self.create_publisher(
            CompressedImage, image_topic, qos_profile_sensor_data)
        self.create_timer(1.0 / frames_per_second, self.publish_frame)
        self.get_logger().info(f'usb webcam {device_index} -> {image_topic}')

    def publish_frame(self):
        has_frame, frame = self.camera.read()
        if not has_frame:
            return
        encoded, buffer = cv2.imencode(
            '.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality])
        if not encoded:
            return
        message = CompressedImage()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.format = 'jpeg'
        message.data = buffer.tobytes()
        self.image_publisher.publish(message)

    def destroy_node(self):
        self.camera.release()
        super().destroy_node()


def main():
    rclpy.init()
    node = UsbWebcam()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
