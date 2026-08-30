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


import importlib.util
import os

import numpy as np


def load_usb_webcam():
    path = os.path.abspath(os.path.join(
        os.path.dirname(__file__), '..', 'src', 'usb_webcam.py'))
    spec = importlib.util.spec_from_file_location('usb_webcam', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


usb_webcam = load_usb_webcam()


class CannedCapture:
    def __init__(self, frame):
        self.frame = frame

    def read(self):
        return self.frame is not None, self.frame

    def release(self):
        pass


def gradient_frame():
    return np.tile(
        np.arange(480, dtype=np.uint8).reshape(-1, 1, 1), (1, 640, 3))


def capture(node):
    images = []
    node.image_publisher.publish = images.append
    return images


def test_a_frame_becomes_a_jpeg_message(usb_webcam_node):
    images = capture(usb_webcam_node)
    usb_webcam_node.camera = CannedCapture(gradient_frame())
    usb_webcam_node.publish_frame()
    assert len(images) == 1
    assert images[0].format == 'jpeg'
    assert bytes(images[0].data[:2]) == b'\xff\xd8'


def test_a_failed_read_publishes_nothing(usb_webcam_node):
    images = capture(usb_webcam_node)
    usb_webcam_node.camera = CannedCapture(None)
    usb_webcam_node.publish_frame()
    assert images == []
