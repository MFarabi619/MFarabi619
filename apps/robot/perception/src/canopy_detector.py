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
from std_srvs.srv import SetBool

JPEG_QUALITY = 80
EXCESS_GREEN_BGR_WEIGHTS = np.array([[-1.0, 2.0, -1.0]], dtype=np.float32)
DENOISE_KERNEL = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
LIVE_PARAMETERS = frozenset({
    'excess_green_min', 'normalize_exposure', 'normalized_green_min',
})


class CanopyDetector(Node):
    def __init__(self, **node_arguments):
        super().__init__('canopy_detector', **node_arguments)
        image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed').value
        mask_topic = self.declare_parameter(
            'mask_topic', 'perception/canopy/mask/compressed').value
        fraction_topic = self.declare_parameter(
            'fraction_topic', 'perception/canopy/fraction').value
        self.excess_green_min = self.declare_parameter('excess_green_min', 20.0).value
        # Absolute excess green scales with exposure, so foliage in the shaded
        # near field falls under the threshold while the sunlit distance passes.
        self.normalize_exposure = self.declare_parameter(
            'normalize_exposure', False).value
        self.normalized_green_min = self.declare_parameter(
            'normalized_green_min', 0.06).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.mask_publisher = self.create_publisher(
            CompressedImage, mask_topic, qos_profile_sensor_data)
        self.fraction_publisher = self.create_publisher(Float32, fraction_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CompressedImage, image_topic, self.on_image, qos_profile_sensor_data)
        self.get_logger().info(f'canopy detector: {image_topic} -> {mask_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_image(self, message):
        if not self.is_enabled:
            return
        image = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if image is None:
            return
        mask = (self.normalized_mask(image) if self.normalize_exposure
                else self.absolute_mask(image))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, DENOISE_KERNEL)
        encoded, buffer = cv2.imencode(
            '.jpg', mask, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        if not encoded:
            return
        mask_message = CompressedImage()
        mask_message.header = message.header
        mask_message.format = 'jpeg'
        mask_message.data = buffer.tobytes()
        self.mask_publisher.publish(mask_message)
        self.fraction_publisher.publish(Float32(data=float(mask.mean() / 255.0)))

    def absolute_mask(self, image):
        excess_green = cv2.transform(image, EXCESS_GREEN_BGR_WEIGHTS)
        otsu_threshold, _ = cv2.threshold(
            excess_green, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        _, mask = cv2.threshold(
            excess_green, max(otsu_threshold, self.excess_green_min), 255,
            cv2.THRESH_BINARY)
        return mask

    def normalized_mask(self, image):
        channels = image.astype(np.float32)
        intensity = channels.sum(axis=2)
        excess_green = cv2.transform(channels, EXCESS_GREEN_BGR_WEIGHTS)
        normalized = np.divide(
            excess_green, intensity,
            out=np.zeros_like(excess_green), where=intensity > 0.0)
        return ((normalized > self.normalized_green_min) * 255).astype(np.uint8)

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)


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
