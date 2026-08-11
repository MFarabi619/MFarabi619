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
import pytest
from sensor_msgs.msg import CompressedImage

LEAF_GREEN = (30, 200, 40)
TARP_GRAY = (150, 150, 150)
SOIL_BROWN = (60, 90, 140)
SHADOW_DARK = (10, 11, 10)


def compressed(image):
    encoded, buffer = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 95])
    assert encoded
    message = CompressedImage()
    message.header.frame_id = 'camera_0_color_optical_frame'
    message.format = 'jpeg'
    message.data = buffer.tobytes()
    return message


def frame(color, width=64, height=48):
    image = np.zeros((height, width, 3), np.uint8)
    image[:] = color
    return image


def capture(node):
    masks = []
    fractions = []
    node.mask_publisher.publish = masks.append
    node.fraction_publisher.publish = fractions.append
    return masks, fractions


def decoded_mask(message):
    return cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_GRAYSCALE)


def test_leaves_classify_green(canopy_detector_node):
    masks, fractions = capture(canopy_detector_node)
    canopy_detector_node.on_image(compressed(frame(LEAF_GREEN)))
    assert fractions[0].data == pytest.approx(1.0, abs=0.02)
    assert decoded_mask(masks[0]).mean() > 250


def test_tarp_and_soil_classify_not_green(canopy_detector_node):
    masks, fractions = capture(canopy_detector_node)
    canopy_detector_node.on_image(compressed(frame(TARP_GRAY)))
    canopy_detector_node.on_image(compressed(frame(SOIL_BROWN)))
    assert fractions[0].data == pytest.approx(0.0, abs=0.02)
    assert fractions[1].data == pytest.approx(0.0, abs=0.02)
    assert decoded_mask(masks[0]).mean() < 5


def test_dark_pixels_filtered_by_excess_green(canopy_detector_node):
    masks, fractions = capture(canopy_detector_node)
    canopy_detector_node.on_image(compressed(frame(SHADOW_DARK)))
    assert fractions[0].data == pytest.approx(0.0, abs=0.02)


def test_fraction_matches_green_share(canopy_detector_node):
    masks, fractions = capture(canopy_detector_node)
    image = frame(TARP_GRAY)
    image[:, :image.shape[1] // 2] = LEAF_GREEN
    canopy_detector_node.on_image(compressed(image))
    assert fractions[0].data == pytest.approx(0.5, abs=0.03)
    mask = decoded_mask(masks[0])
    assert mask[:, :20].mean() > 240
    assert mask[:, -20:].mean() < 15


def test_mask_keeps_camera_header(canopy_detector_node):
    masks, fractions = capture(canopy_detector_node)
    canopy_detector_node.on_image(compressed(frame(LEAF_GREEN)))
    assert masks[0].header.frame_id == 'camera_0_color_optical_frame'
    assert masks[0].format == 'jpeg'
