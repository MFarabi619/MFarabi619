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


import json
from pathlib import Path

import pytest

from robot_machines.machine import (
    CAMERA_MODELS, GPS_MODELS, IMU_MODELS, MachineError, load_machine, machine_names)
from robot_machines.schema import SCHEMA_PATH, robot_schema

DRIVER_LAUNCH_DIRECTORY = Path(__file__).resolve().parents[2] / 'drivers' / 'launch'
SCHEMA_MODELINE = '# yaml-language-server: $schema=../robot.schema.json'


@pytest.mark.parametrize('name', machine_names())
def test_every_machine_file_matches_the_schema(name):
    machine = load_machine(name)
    assert machine.name == name
    assert machine.has_arm or machine.platform is not None


def write_machine(root, name, body):
    (root / name).mkdir()
    (root / name / 'robot.yaml').write_text(f'system: {{namespace: {name}}}\n{body}')


def test_unknown_keys_are_rejected(tmp_path):
    write_machine(tmp_path, 'typo', 'platform: {drivetrain: {modle: roboteq}}\n')
    with pytest.raises(MachineError, match=r'platform\.drivetrain\.modle'):
        load_machine('typo', tmp_path)


def test_missing_machine_file_is_named(tmp_path):
    with pytest.raises(MachineError, match='ghost has no robot.yaml'):
        load_machine('ghost', tmp_path)


def test_nav2_person_follow_and_gps_navigation_are_refused(tmp_path):
    write_machine(
        tmp_path, 'twice',
        'platform: {}\nbehaviors: {nav2_person_follow: true, gps_navigation: true}\n')
    with pytest.raises(MachineError, match='enable one'):
        load_machine('twice', tmp_path)


def test_nav2_person_follow_and_nav2_navigate_to_pose_are_refused(tmp_path):
    write_machine(
        tmp_path, 'twice',
        'platform: {}\nbehaviors: {nav2_person_follow: true, nav2_navigate_to_pose: true}\n')
    with pytest.raises(MachineError, match='enable one'):
        load_machine('twice', tmp_path)


def test_unknown_sensor_models_are_listed_against_the_known_ones(tmp_path):
    write_machine(tmp_path, 'typo', 'platform: {}\nsensors:\n  camera:\n    - {model: oak_d}\n')
    with pytest.raises(MachineError, match="Input should be 'luxonis_oak_d_sr'.*'stereolabs_zed'"):
        load_machine('typo', tmp_path)


@pytest.mark.parametrize('model', CAMERA_MODELS + IMU_MODELS + GPS_MODELS)
def test_every_sensor_model_has_a_driver_launch_file(model):
    assert (DRIVER_LAUNCH_DIRECTORY / f'{model}.launch.py').is_file()


def test_sensors_are_named_by_index(tmp_path):
    write_machine(
        tmp_path, 'eyes',
        'sensors:\n  camera:\n    - {model: luxonis_oak_d_sr}\n'
        '    - {model: orbbec_gemini_335l, parameters: {enable_depth: true}}\n')
    cameras = load_machine('eyes', tmp_path).sensors.camera
    assert [camera.name for camera in cameras] == ['camera_0', 'camera_1']


def test_depth_camera_prefers_oak_then_orbbec_then_zed(tmp_path):
    zed = '    - {model: stereolabs_zed}\n'
    orbbec = '    - {model: orbbec_gemini_335l, parameters: {enable_depth: true}}\n'
    oak = '    - {model: luxonis_oak_d_pro_w_poe}\n'
    write_machine(tmp_path, 'all', 'sensors:\n  camera:\n' + zed + orbbec + oak)
    write_machine(tmp_path, 'no_oak', 'sensors:\n  camera:\n' + zed + orbbec)
    write_machine(tmp_path, 'zed_only', 'sensors:\n  camera:\n' + zed)
    write_machine(tmp_path, 'blind', 'sensors:\n  camera: []\n')
    assert load_machine('all', tmp_path).depth_camera.model == 'luxonis_oak_d_pro_w_poe'
    assert load_machine('no_oak', tmp_path).depth_camera.model == 'orbbec_gemini_335l'
    assert load_machine('zed_only', tmp_path).depth_camera.model == 'stereolabs_zed'
    assert load_machine('blind', tmp_path).depth_camera is None


def test_has_on_camera_detector_follows_the_camera_model():
    assert load_machine('kinova-link-6').depth_camera.has_on_camera_detector
    assert not load_machine('jiro').depth_camera.has_on_camera_detector


def test_committed_schema_matches_the_model():
    assert json.loads(SCHEMA_PATH.read_text()) == robot_schema()


@pytest.mark.parametrize('name', machine_names())
def test_every_machine_file_points_editors_at_the_schema(name):
    first_line = (SCHEMA_PATH.parent / name / 'robot.yaml').read_text().splitlines()[0]
    assert first_line == SCHEMA_MODELINE


def test_domains_follow_the_hardware_and_behaviors():
    assert load_machine('taro').domains == ('platform', 'sensors', 'perception', 'navigation')
    assert load_machine('kinova-link-6').domains == ('sensors', 'perception', 'manipulation')
    assert load_machine('pocketbeagle-2').domains == ('platform',)


def test_node_tuning_is_keyed_by_node_name():
    assert load_machine('jiro').ros_parameters['line_follow'] == {'image_width_pixels': 640}
    assert 'line_follow' not in load_machine('taro').ros_parameters
    assert load_machine('pocketbeagle-2').ros_parameters == {}


def test_model_scoped_motion_limits_override_the_drivetrain_limits():
    drivetrain = load_machine('taro').platform.drivetrain
    assert drivetrain.motion_limits('roboteq') == {
        'max_linear_acceleration_meters_per_second_squared': 5.0,
        'max_angular_acceleration_radians_per_second_squared': 7.5,
    }
    assert drivetrain.motion_limits('rc_pulse')['max_linear_velocity_meters_per_second'] == 1.37


def test_arm_only_machine_has_no_platform():
    assert load_machine('kinova-link-6').is_arm_only
    assert not load_machine('taro').has_arm


def test_arm_mounted_on_a_chassis_is_not_arm_only(tmp_path):
    write_machine(tmp_path, 'carrier', (
        'platform: {drivetrain: {model: mock}}\n'
        'manipulators:\n'
        '  arms:\n'
        '    - {model: kinova_link6, parent: chassis, xyz: [0.35, 0.0, 0.114],'
        ' gripper: {model: robotiq_2f_85}}\n'))
    machine = load_machine('carrier', tmp_path)
    arm = machine.manipulators.arms[0]
    assert machine.has_arm and not machine.is_arm_only
    assert (arm.parent, arm.xyz) == ('chassis', [0.35, 0.0, 0.114])
    assert arm.packages.description == 'link6_description'
    assert arm.name == 'arm_0'
    assert not machine.manipulators.moveit.enable


def test_disabled_arm_is_declared_but_not_launched(tmp_path):
    write_machine(tmp_path, 'carrier', (
        'platform: {drivetrain: {model: mock}}\n'
        'manipulators:\n'
        '  arms:\n'
        '    - {model: kinova_link6, launch_enabled: false}\n'))
    machine = load_machine('carrier', tmp_path)
    assert machine.has_arm and not machine.enabled_arms
    assert 'manipulation' not in machine.domains


def test_camera_queries_by_model():
    kinova = load_machine('kinova-link-6')
    assert kinova.has_stereolabs_zed
    assert kinova.first_enabled_camera('stereolabs_zed').name == 'camera_0'
    assert load_machine('pocketbeagle-2').enabled_cameras == []


def test_absent_drivetrain_model_means_pwm_dir():
    assert load_machine('pocketbeagle-2').platform.drivetrain.model == 'pwm_dir'


def test_rc_receiver_launch_enabled_is_per_machine():
    assert load_machine('jiro').platform.rc_receiver.launch_enabled
    assert not load_machine('taro').platform.rc_receiver.launch_enabled


def test_drivetrain_sides_carry_their_direction():
    drivetrain = load_machine('taro').platform.drivetrain
    assert not drivetrain.left.is_reversed
    assert drivetrain.right.is_reversed
