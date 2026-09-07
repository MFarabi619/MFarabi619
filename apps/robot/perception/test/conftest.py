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
import sys

import pytest
import rclpy

SRC_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src'))
if SRC_DIRECTORY not in sys.path:
    sys.path.insert(0, SRC_DIRECTORY)


def load_module(module_name):
    path = os.path.join(SRC_DIRECTORY, f'{module_name}.py')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_node_class(module_name, class_name):
    return getattr(load_module(module_name), class_name)


@pytest.fixture(scope='session', autouse=True)
def ros_context():
    owns_context = not rclpy.ok()
    if owns_context:
        rclpy.init()
    yield
    if owns_context and rclpy.ok():
        rclpy.shutdown()


@pytest.fixture
def approach_node():
    node = load_node_class('approach', 'Approach')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def tracked_approach_node():
    node = load_node_class('tracked_approach', 'Approach')()
    yield node
    node.destroy_node()


@pytest.fixture
def row_follow_node():
    node = load_node_class('row_follow', 'RowFollow')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def color_blob_detector_node():
    node = load_node_class('color_blob_detector', 'ColorBlobDetector')()
    node.is_enabled = False
    yield node
    node.destroy_node()


@pytest.fixture
def brightness_detector_node():
    node = load_node_class('surface_detector', 'SurfaceDetector')(
        parameter_overrides=[
            rclpy.parameter.Parameter('mask_source', value='brightness'),
            rclpy.parameter.Parameter('max_value', value=0.35),
            rclpy.parameter.Parameter('max_saturation', value=0.75),
            rclpy.parameter.Parameter('roi_top_fraction', value=0.5),
            rclpy.parameter.Parameter('min_fraction', value=0.6),
            rclpy.parameter.Parameter('max_detections_per_second', value=1000.0),
        ])
    yield node
    node.destroy_node()


@pytest.fixture
def surface_follow_node():
    node = load_node_class('surface_follow', 'SurfaceFollow')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def green_detector_node():
    node = load_node_class('green_detector', 'GreenDetector')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def row_navigator_node():
    node = load_node_class('row_navigator', 'RowNavigator')()
    node.drive_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture(scope='session')
def voice_word_detector_module():
    return load_module('voice_word_detector')


@pytest.fixture
def voice_word_detector_node(voice_word_detector_module):
    node = voice_word_detector_module.VoiceWordDetector()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture(scope='session')
def voice_transcriber_module():
    return load_module('voice_transcriber')


@pytest.fixture
def voice_transcriber_node(voice_transcriber_module):
    node = voice_transcriber_module.VoiceTranscriber()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture(scope='session')
def voice_speaker_module():
    return load_module('voice_speaker')


@pytest.fixture
def voice_speaker_node(voice_speaker_module):
    node = voice_speaker_module.VoiceSpeaker()
    yield node
    node.destroy_node()


@pytest.fixture(scope='session')
def voice_teleop_module():
    return load_module('voice_teleop')


@pytest.fixture
def voice_teleop_node(voice_teleop_module):
    node = voice_teleop_module.VoiceTeleop()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def canopy_detector_node():
    node = load_node_class('canopy_detector', 'CanopyDetector')()
    yield node
    node.destroy_node()


@pytest.fixture
def normalized_canopy_detector_node():
    node = load_node_class('canopy_detector', 'CanopyDetector')(
        parameter_overrides=[
            rclpy.parameter.Parameter('normalize_exposure', value=True),
            rclpy.parameter.Parameter('normalized_excess_green_min', value=0.06),
        ])
    yield node
    node.destroy_node()


@pytest.fixture
def cloud_optical_adapter_node():
    node = load_node_class('cloud_optical_adapter', 'CloudOpticalAdapter')()
    yield node
    node.destroy_node()


@pytest.fixture
def lay_down_weeding_elbow_teleop_node():
    node = load_node_class(
        'lay_down_weeding_elbow_teleop', 'LayDownWeedingElbowTeleop')(
        parameter_overrides=[
            rclpy.parameter.Parameter('neutral_sample_frames', value=4),
            rclpy.parameter.Parameter('commit_frames', value=2),
            rclpy.parameter.Parameter('command_smoothing_seconds', value=0.0),
            rclpy.parameter.Parameter('max_detections_per_second', value=0.0),
        ])
    pose_landmarker = node.landmarker
    node.is_enabled = True
    yield node
    node.destroy_node()
    pose_landmarker.close()


@pytest.fixture
def harvest_lane_navigator_node():
    node = load_node_class('harvest_lane_navigator', 'HarvestLaneNavigator')()
    node.is_enabled = True
    yield node
    node.destroy_node()
