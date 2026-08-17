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


import time

import cv2
import depthai as dai
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, CompressedImage, Image


QUEUE_POLL_RATE_HZ = 60.0
DEVICE_RETRY_DELAY_SECONDS = 2.0
MAX_PREVIEW_DEPTH_MM = 3000.0
SENSOR_WIDTH = 1280
SENSOR_HEIGHT = 800
BYTES_PER_DEPTH_PIXEL = 2


# TODO: align depth to CAM_B color on device
# TODO: add on-device threshold filter clamped to the 0.2-1.5m band
# TODO: publish the onboard BMI270 imu
# TODO: run spatial person detection on camera
def build_pipeline(fps, jpeg_quality, resolution_divisor):
    pipeline = dai.Pipeline()
    left = pipeline.create(dai.node.ColorCamera)
    right = pipeline.create(dai.node.ColorCamera)
    stereo = pipeline.create(dai.node.StereoDepth)
    color_encoder = pipeline.create(dai.node.VideoEncoder)
    color_output = pipeline.create(dai.node.XLinkOut)
    depth_output = pipeline.create(dai.node.XLinkOut)
    color_output.setStreamName('color')
    depth_output.setStreamName('depth')
    for camera, socket in ((left, 'left'), (right, 'right')):
        camera.setResolution(
            dai.ColorCameraProperties.SensorResolution.THE_800_P)
        camera.setCamera(socket)
        camera.setFps(fps)
        camera.setIspScale(1, resolution_divisor)
    stereo.setDefaultProfilePreset(
        dai.node.StereoDepth.PresetMode.HIGH_DENSITY)
    stereo.initialConfig.setMedianFilter(dai.MedianFilter.KERNEL_7x7)
    stereo.setLeftRightCheck(True)
    stereo.setSubpixel(True)
    color_encoder.setDefaultProfilePreset(
        fps, dai.VideoEncoderProperties.Profile.MJPEG)
    color_encoder.setQuality(jpeg_quality)
    left.isp.link(stereo.left)
    right.isp.link(stereo.right)
    left.video.link(color_encoder.input)
    color_encoder.bitstream.link(color_output.input)
    stereo.depth.link(depth_output.input)
    return pipeline


class OakDSr(Node):
    def __init__(self):
        super().__init__('oak_d_sr')
        self.declare_parameter('fps', 15.0)
        self.declare_parameter('jpeg_quality', 60)
        self.declare_parameter('frame_id', 'camera_0_link')
        self.declare_parameter('resolution_divisor', 2)
        self.frame_id = self.get_parameter('frame_id').value
        self.jpeg_quality = self.get_parameter('jpeg_quality').value
        resolution_divisor = self.get_parameter('resolution_divisor').value
        self.frame_width = SENSOR_WIDTH // resolution_divisor
        self.frame_height = SENSOR_HEIGHT // resolution_divisor
        self.pipeline = build_pipeline(
            self.get_parameter('fps').value, self.jpeg_quality,
            resolution_divisor)
        self.connect()
        self.color_publisher = self.create_publisher(
            CompressedImage, 'color/image_raw/compressed', qos_profile_sensor_data)
        self.depth_publisher = self.create_publisher(
            Image, 'depth/image_raw', qos_profile_sensor_data)
        self.depth_preview_publisher = self.create_publisher(
            CompressedImage, 'depth/image_raw/compressed',
            qos_profile_sensor_data)
        self.color_camera_info_publisher = self.create_publisher(
            CameraInfo, 'color/camera_info', qos_profile_sensor_data)
        self.depth_camera_info_publisher = self.create_publisher(
            CameraInfo, 'depth/camera_info', qos_profile_sensor_data)
        self.poll_timer = self.create_timer(
            1.0 / QUEUE_POLL_RATE_HZ, self.poll_queues)

    def connect(self):
        self.device = self.wait_for_device(self.pipeline)
        self.color_queue = self.device.getOutputQueue(
            'color', maxSize=2, blocking=False)
        self.depth_queue = self.device.getOutputQueue(
            'depth', maxSize=2, blocking=False)
        calibration = self.device.readCalibration()
        self.color_camera_info = self.read_camera_info(
            calibration, dai.CameraBoardSocket.CAM_B)
        self.depth_camera_info = self.read_camera_info(
            calibration, dai.CameraBoardSocket.CAM_C)
        self.get_logger().info(
            f'connected {self.device.getDeviceName()} '
            f'usb={self.device.getUsbSpeed().name}')

    def release_device(self):
        try:
            self.device.close()
        except RuntimeError:
            pass

    def wait_for_device(self, pipeline):
        while rclpy.ok():
            try:
                return dai.Device(pipeline)
            except RuntimeError as error:
                self.get_logger().warning(f'waiting for camera: {error}')
                time.sleep(DEVICE_RETRY_DELAY_SECONDS)
        raise RuntimeError('shutdown before camera appeared')

    def read_camera_info(self, calibration, socket):
        intrinsics = calibration.getCameraIntrinsics(
            socket, self.frame_width, self.frame_height)
        camera_info = CameraInfo()
        camera_info.width = self.frame_width
        camera_info.height = self.frame_height
        camera_info.distortion_model = 'plumb_bob'
        camera_info.d = [0.0] * 5
        camera_info.k = [value for row in intrinsics for value in row]
        camera_info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        camera_info.p = [
            camera_info.k[0], 0.0, camera_info.k[2], 0.0,
            0.0, camera_info.k[4], camera_info.k[5], 0.0,
            0.0, 0.0, 1.0, 0.0,
        ]
        return camera_info

    def poll_queues(self):
        try:
            for frame in self.color_queue.tryGetAll():
                self.publish_color(frame)
            for frame in self.depth_queue.tryGetAll():
                self.publish_depth(frame)
        except RuntimeError as error:
            self.get_logger().warning(f'camera lost, reconnecting: {error}')
            self.release_device()
            self.connect()

    def stamp_header(self, message):
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id

    def publish_color(self, frame):
        self.stamp_header(self.color_camera_info)
        self.color_camera_info_publisher.publish(self.color_camera_info)
        if self.color_publisher.get_subscription_count() == 0:
            return
        message = CompressedImage()
        self.stamp_header(message)
        message.format = 'jpeg'
        message.data = frame.getData().tobytes()
        self.color_publisher.publish(message)

    def publish_depth(self, frame):
        self.stamp_header(self.depth_camera_info)
        self.depth_camera_info_publisher.publish(self.depth_camera_info)
        wants_raw = self.depth_publisher.get_subscription_count() > 0
        wants_preview = (
            self.depth_preview_publisher.get_subscription_count() > 0)
        if not wants_raw and not wants_preview:
            return
        depth = frame.getFrame()
        if wants_raw:
            message = Image()
            self.stamp_header(message)
            message.height, message.width = depth.shape
            message.encoding = '16UC1'
            message.step = message.width * BYTES_PER_DEPTH_PIXEL
            message.data = depth.tobytes()
            self.depth_publisher.publish(message)
        if wants_preview:
            scaled = cv2.convertScaleAbs(depth, alpha=255.0 / MAX_PREVIEW_DEPTH_MM)
            colored = cv2.applyColorMap(scaled, cv2.COLORMAP_JET)
            success, encoded = cv2.imencode(
                '.jpg', colored,
                [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality])
            if not success:
                return
            message = CompressedImage()
            self.stamp_header(message)
            message.format = 'jpeg'
            message.data = encoded.tobytes()
            self.depth_preview_publisher.publish(message)


def main():
    rclpy.init()
    node = OakDSr()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.release_device()


if __name__ == '__main__':
    main()
