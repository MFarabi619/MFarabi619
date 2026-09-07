#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


import math
import threading

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from rpicam_mjpeg import frames
from sensor_msgs.msg import CameraInfo, CompressedImage


def pinhole_intrinsics(width, height, fov_degrees):
    focal = (width / 2.0) / math.tan(math.radians(fov_degrees) / 2.0)
    return focal, focal, width / 2.0, height / 2.0


class MjpegCamera(Node):
    def __init__(self):
        super().__init__('camera')
        self.name = self.declare_parameter('name', 'camera_0').value
        self.host = self.declare_parameter('host', '192.168.12.119').value
        self.port = self.declare_parameter('port', 8887).value
        self.image_topic = self.declare_parameter(
            'image_topic', 'color/image_raw/compressed'
        ).value
        self.camera_info_topic = self.declare_parameter(
            'camera_info_topic', 'color/camera_info'
        ).value
        self.frame_id = self.declare_parameter(
            'frame_id', f'{self.name}_color_optical_frame'
        ).value
        self.stream_path = self.declare_parameter('stream_path', '/stream').value
        width = self.declare_parameter('width', 1280).value
        height = self.declare_parameter('height', 720).value
        fov_degrees = self.declare_parameter('fov_degrees', 90.0).value
        self.publish_period = 1.0 / self.declare_parameter('publish_rate', 20.0).value

        self.image_publisher = self.create_publisher(
            CompressedImage, self.image_topic, qos_profile_sensor_data
        )
        self.camera_info_publisher = self.create_publisher(
            CameraInfo, self.camera_info_topic, qos_profile_sensor_data
        )
        self.camera_info = self._build_camera_info(width, height, fov_degrees)

        self.stopped = threading.Event()
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()

    def _build_camera_info(self, width, height, fov_degrees):
        focal_x, focal_y, center_x, center_y = pinhole_intrinsics(width, height, fov_degrees)
        info = CameraInfo()
        info.width = int(width)
        info.height = int(height)
        info.distortion_model = 'plumb_bob'
        info.d = [0.0] * 5
        info.k = [focal_x, 0.0, center_x, 0.0, focal_y, center_y, 0.0, 0.0, 1.0]
        info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        info.p = [focal_x, 0.0, center_x, 0.0, 0.0, focal_y, center_y, 0.0, 0.0, 0.0, 1.0, 0.0]
        return info

    def _read_loop(self):
        while not self.stopped.is_set() and rclpy.ok():
            try:
                self._stream()
            except OSError as error:
                self.get_logger().warning(
                    f'camera stream {self.host}:{self.port} lost ({error}); retrying'
                )
                self.stopped.wait(1.0)

    def _stream(self):
        self.get_logger().info(
            f'streaming camera from {self.host}:{self.port} -> {self.image_topic}'
        )
        last_publish = 0.0
        stream = frames(self.host, self.port, self.stream_path)
        try:
            for frame in stream:
                if self.stopped.is_set() or not rclpy.ok():
                    break
                seconds = self.get_clock().now().nanoseconds / 1e9
                if seconds - last_publish < self.publish_period:
                    continue
                last_publish = seconds
                self._publish(frame)
        finally:
            stream.close()

    def _publish(self, frame):
        stamp = self.get_clock().now().to_msg()
        image = CompressedImage()
        image.header.stamp = stamp
        image.header.frame_id = self.frame_id
        image.format = 'jpeg'
        image.data = frame
        self.image_publisher.publish(image)
        self.camera_info.header.stamp = stamp
        self.camera_info.header.frame_id = self.frame_id
        self.camera_info_publisher.publish(self.camera_info)

    def destroy_node(self):
        self.stopped.set()
        super().destroy_node()


def main():
    rclpy.init()
    node = MjpegCamera()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
