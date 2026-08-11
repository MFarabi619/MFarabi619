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


import numpy as np
import pytest

BRIGHT_GREEN = (0, 255, 0)
DARK_GREEN = (20, 70, 30)


def scene(fill_color, box):
    image = np.zeros((120, 160, 3), np.uint8)
    x, y, w, h = box
    image[y:y + h, x:x + w] = fill_color
    return image


def test_mask_catches_bright_green(green_detector_node):
    mask = green_detector_node.green_mask(scene(BRIGHT_GREEN, (50, 30, 60, 60)))
    assert mask[60, 80] == 255
    assert mask[5, 5] == 0


def test_mask_rejects_dark_dull_green(green_detector_node):
    mask = green_detector_node.green_mask(scene(DARK_GREEN, (50, 30, 60, 60)))
    assert mask.sum() == 0


def test_detect_blobs_reports_box_above_area(green_detector_node):
    green_detector_node.min_blob_area = 100
    blobs = green_detector_node.detect_blobs(
        green_detector_node.green_mask(scene(BRIGHT_GREEN, (50, 30, 60, 60))))
    assert len(blobs) == 1
    (x, y, w, h), fill = blobs[0]
    assert w == pytest.approx(60, abs=2)
    assert h == pytest.approx(60, abs=2)
    assert fill == pytest.approx(1.0, abs=0.05)


def test_detect_blobs_rejects_below_area(green_detector_node):
    green_detector_node.min_blob_area = 5000
    blobs = green_detector_node.detect_blobs(
        green_detector_node.green_mask(scene(BRIGHT_GREEN, (50, 30, 10, 10))))
    assert blobs == []
