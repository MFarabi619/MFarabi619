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


import glob
import os

import cv2
import numpy as np
import pytest
import rclpy.parameter
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool

FIELD_FRAMES = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..', '..',
    'assets', 'datasets', 'area_xo', 'taro_harvest_lane_frames'))
NEAR_FIELD_TOP = 0.78
SKY_BOTTOM = 0.40


def field_frames():
    return sorted(glob.glob(os.path.join(FIELD_FRAMES, '*.jpg')))


def coverage(mask, top_fraction, bottom_fraction):
    height = mask.shape[0]
    band = mask[int(top_fraction * height):int(bottom_fraction * height)]
    return float((band > 0).mean())


def lit_and_shaded_foliage():
    """Same leaf colour at two exposures, as the near and far field see it."""
    image = np.zeros((100, 40, 3), np.uint8)
    image[:50] = (40, 110, 45)
    image[50:] = (14, 38, 16)
    return image


def compressed(image):
    encoded, buffer = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 95])
    assert encoded
    message = CompressedImage()
    message.format = 'jpeg'
    message.data = buffer.tobytes()
    return message


def test_a_disabled_detector_publishes_nothing(canopy_detector_node):
    published = []
    canopy_detector_node.mask_publisher.publish = published.append
    canopy_detector_node.fraction_publisher.publish = published.append
    canopy_detector_node.is_enabled = False
    canopy_detector_node.on_image(compressed(lit_and_shaded_foliage()))
    assert published == []


def test_enabling_resumes_publishing(canopy_detector_node):
    published = []
    canopy_detector_node.mask_publisher.publish = published.append
    canopy_detector_node.fraction_publisher.publish = published.append
    canopy_detector_node.on_enable(SetBool.Request(data=True), SetBool.Response())
    canopy_detector_node.on_image(compressed(lit_and_shaded_foliage()))
    assert len(published) == 2


def test_the_threshold_retunes_without_a_restart(normalized_canopy_detector_node):
    normalized_canopy_detector_node.set_parameters(
        [rclpy.parameter.Parameter('normalized_excess_green_min', value=0.9)])
    mask = normalized_canopy_detector_node.normalized_mask(lit_and_shaded_foliage())
    assert not mask.any()


def test_absolute_index_loses_foliage_once_it_is_shaded(canopy_detector_node):
    mask = canopy_detector_node.absolute_mask(lit_and_shaded_foliage())
    assert (mask[:50] > 0).mean() > 0.9
    assert (mask[50:] > 0).mean() < 0.1


def test_normalized_index_keeps_shaded_foliage(normalized_canopy_detector_node):
    mask = normalized_canopy_detector_node.normalized_mask(lit_and_shaded_foliage())
    assert (mask[:50] > 0).mean() > 0.9
    assert (mask[50:] > 0).mean() > 0.9


def test_normalized_mask_is_a_byte_mask(normalized_canopy_detector_node):
    mask = normalized_canopy_detector_node.normalized_mask(lit_and_shaded_foliage())
    assert mask.dtype == np.uint8
    assert set(np.unique(mask)) <= {0, 255}
    assert mask.shape == (100, 40)


def test_normalized_mask_survives_pure_black_pixels(normalized_canopy_detector_node):
    mask = normalized_canopy_detector_node.normalized_mask(
        np.zeros((8, 8, 3), np.uint8))
    assert not mask.any()


@pytest.mark.parametrize('frame_path', field_frames())
def test_normalized_index_finds_more_near_canopy_on_the_real_rows(
        canopy_detector_node, normalized_canopy_detector_node, frame_path):
    image = cv2.imread(frame_path)
    assert image is not None, frame_path
    absolute = canopy_detector_node.absolute_mask(image)
    normalized = normalized_canopy_detector_node.normalized_mask(image)
    assert (coverage(normalized, NEAR_FIELD_TOP, 1.0)
            > coverage(absolute, NEAR_FIELD_TOP, 1.0))


@pytest.mark.parametrize('frame_path', field_frames())
def test_neither_index_mistakes_sky_for_canopy(
        canopy_detector_node, normalized_canopy_detector_node, frame_path):
    image = cv2.imread(frame_path)
    for mask in (canopy_detector_node.absolute_mask(image),
                 normalized_canopy_detector_node.normalized_mask(image)):
        assert coverage(mask, 0.0, SKY_BOTTOM) < 0.01
