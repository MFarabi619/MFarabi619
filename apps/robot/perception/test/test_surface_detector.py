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
import rclpy.parameter
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool

IMAGE_WIDTH = 640
IMAGE_HEIGHT = 400
PATH_LEFT = 260
PATH_RIGHT = 380
BRIGHT_SURROUND = (120, 150, 160)
DARK_PATH = (60, 60, 62)


def frame_with_dark_path():
    image = np.zeros((IMAGE_HEIGHT, IMAGE_WIDTH, 3), np.uint8)
    image[:] = BRIGHT_SURROUND
    image[:, PATH_LEFT:PATH_RIGHT] = DARK_PATH
    return image


def compressed(image):
    encoded, buffer = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 95])
    assert encoded
    message = CompressedImage()
    message.header.frame_id = 'camera_0_color_optical_frame'
    message.format = 'jpeg'
    message.data = buffer.tobytes()
    return message


def capture(node):
    detections = []
    node.detections_publisher.publish = detections.append
    node.overlay_publisher.publish = lambda message: None
    return detections


def enable(node):
    node.on_enable(SetBool.Request(data=True), SetBool.Response())


def test_brightness_mode_does_not_load_a_segmentation_model(brightness_detector_node):
    assert brightness_detector_node.session is None


def test_disabled_detector_runs_no_inference(brightness_detector_node):
    detections = capture(brightness_detector_node)
    brightness_detector_node.on_image(compressed(frame_with_dark_path()))
    assert detections == []
    assert brightness_detector_node.previous_detection_time is None


def test_enabled_detector_finds_the_dark_path(brightness_detector_node):
    detections = capture(brightness_detector_node)
    enable(brightness_detector_node)
    brightness_detector_node.on_image(compressed(frame_with_dark_path()))
    assert len(detections) == 1
    found = detections[0].detections
    assert len(found) == 1
    centre = found[0].bbox.center.position.x
    assert PATH_LEFT < centre < PATH_RIGHT


def test_brightness_mask_rejects_surfaces_brighter_than_the_ceiling(
        brightness_detector_node):
    detections = capture(brightness_detector_node)
    enable(brightness_detector_node)
    uniform = np.zeros((IMAGE_HEIGHT, IMAGE_WIDTH, 3), np.uint8)
    uniform[:] = BRIGHT_SURROUND
    brightness_detector_node.on_image(compressed(uniform))
    assert detections[0].detections == []


def test_unknown_mask_source_falls_back_instead_of_crashing(brightness_detector_node):
    node = type(brightness_detector_node)(
        parameter_overrides=[
            rclpy.parameter.Parameter('mask_source', value='brightnes')])
    try:
        assert node.mask_source == 'brightness'
        assert node.session is None
    finally:
        node.destroy_node()


def test_unusable_live_values_are_rejected(brightness_detector_node):
    for name, value in (('smooth_window', 0), ('smooth_window', -3),
                        ('max_value', 1.5), ('max_value', -0.2),
                        ('mask_source', 'segmentation')):
        result = brightness_detector_node.set_parameters(
            [rclpy.parameter.Parameter(name, value=value)])
        assert not result[0].successful, f'{name}={value} was accepted'
    assert brightness_detector_node.mask_source == 'brightness'


def test_disabling_after_use_stops_further_inference(brightness_detector_node):
    detections = capture(brightness_detector_node)
    enable(brightness_detector_node)
    brightness_detector_node.on_image(compressed(frame_with_dark_path()))
    brightness_detector_node.on_enable(
        SetBool.Request(data=False), SetBool.Response())
    published = len(detections)
    brightness_detector_node.on_image(compressed(frame_with_dark_path()))
    assert len(detections) == published
