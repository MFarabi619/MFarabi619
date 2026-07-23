#!/usr/bin/env python3

import os
import sys
import threading

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '..', 'drivers'))

import rclpy
from orbbec_gemini_335l import OrbbecGemini335L
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, CompressedImage


class OrbbecCamera(Node):
    def __init__(self):
        super().__init__('camera')
        self.declare_parameter('width', 640)
        self.declare_parameter('height', 480)
        self.declare_parameter('fps', 30)
        self.declare_parameter('frame_id', 'camera_0_color_optical_frame')
        self.frame_id = self.get_parameter('frame_id').value
        self.camera = OrbbecGemini335L(
            self.get_parameter('width').value,
            self.get_parameter('height').value,
            self.get_parameter('fps').value)
        self.image_publisher = self.create_publisher(
            CompressedImage, 'color/image_raw/compressed',
            qos_profile_sensor_data)
        self.camera_info_publisher = self.create_publisher(
            CameraInfo, 'color/camera_info', 10)
        self.camera_info = None
        self.create_timer(1.0, self.publish_camera_info)
        threading.Thread(target=self.publish_frames, daemon=True).start()

    def publish_frames(self):
        for jpeg in self.camera.frames():
            message = CompressedImage()
            message.header.stamp = self.get_clock().now().to_msg()
            message.header.frame_id = self.frame_id
            message.format = 'jpeg'
            message.data = jpeg
            self.image_publisher.publish(message)

    def publish_camera_info(self):
        if self.camera_info is None:
            intrinsic, distortion = self.camera.color_calibration()
            if intrinsic.width == 0:
                return
            camera_info = CameraInfo()
            camera_info.header.frame_id = self.frame_id
            camera_info.width = intrinsic.width
            camera_info.height = intrinsic.height
            camera_info.distortion_model = 'plumb_bob'
            camera_info.d = [
                distortion.k1, distortion.k2,
                distortion.p1, distortion.p2, distortion.k3,
            ]
            camera_info.k = [
                intrinsic.fx, 0.0, intrinsic.cx,
                0.0, intrinsic.fy, intrinsic.cy,
                0.0, 0.0, 1.0,
            ]
            camera_info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
            camera_info.p = [
                intrinsic.fx, 0.0, intrinsic.cx, 0.0,
                0.0, intrinsic.fy, intrinsic.cy, 0.0,
                0.0, 0.0, 1.0, 0.0,
            ]
            self.camera_info = camera_info
        self.camera_info.header.stamp = self.get_clock().now().to_msg()
        self.camera_info_publisher.publish(self.camera_info)


def main():
    rclpy.init()
    node = OrbbecCamera()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.camera.close()


if __name__ == '__main__':
    main()
