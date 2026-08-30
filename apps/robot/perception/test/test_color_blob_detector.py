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
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool

BRIGHT_LINE = (240, 240, 240)
DARK_FLOOR = (40, 45, 50)


def frame_with_bright_line():
    image = np.zeros((240, 320, 3), np.uint8)
    image[:] = DARK_FLOOR
    image[:, 140:180] = BRIGHT_LINE
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


def test_disabled_detector_publishes_nothing(color_blob_detector_node):
    detections = capture(color_blob_detector_node)
    color_blob_detector_node.on_image(compressed(frame_with_bright_line()))
    assert detections == []


def test_enabling_starts_publishing(color_blob_detector_node):
    detections = capture(color_blob_detector_node)
    color_blob_detector_node.on_enable(
        SetBool.Request(data=True), SetBool.Response())
    color_blob_detector_node.on_image(compressed(frame_with_bright_line()))
    assert len(detections) == 1


def test_max_value_ceiling_excludes_pixels_brighter_than_the_limit(
        color_blob_detector_node):
    color_blob_detector_node.hue_min = 0.0
    color_blob_detector_node.hue_max = 180.0
    color_blob_detector_node.min_saturation = 0.0
    color_blob_detector_node.min_value = 0.0
    frame = frame_with_bright_line()
    line_columns = slice(145, 175)

    color_blob_detector_node.max_value = 1.0
    assert color_blob_detector_node.blob_mask(frame)[:, line_columns].any()

    color_blob_detector_node.max_value = 0.5
    assert not color_blob_detector_node.blob_mask(frame)[:, line_columns].any()
