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


import pytest

from machine import MachineError, load_machine, machine_names


@pytest.mark.parametrize('name', machine_names())
def test_every_machine_file_matches_the_schema(name):
    machine = load_machine(name)
    assert machine.name == name
    assert machine.has_arm or machine.platform is not None


def test_unknown_keys_are_rejected(tmp_path):
    (tmp_path / 'typo').mkdir()
    (tmp_path / 'typo' / 'robot.yaml').write_text(
        'serial_number: mark-0\nversion: 1\nsystem: {namespace: typo}\n'
        'platform: {drivetrain: {modle: roboteq}}\n')
    with pytest.raises(MachineError, match=r"drivetrain: unknown keys \['modle'\]"):
        load_machine('typo', tmp_path)


def test_version_zero_is_refused(tmp_path):
    (tmp_path / 'old').mkdir()
    (tmp_path / 'old' / 'robot.yaml').write_text('serial_number: mark-0\n')
    with pytest.raises(MachineError, match='schema version 0'):
        load_machine('old', tmp_path)


def test_model_scoped_motion_limits_override_the_drivetrain_limits():
    drivetrain = load_machine('taro').platform.drivetrain
    assert drivetrain.motion_limits('roboteq') == {
        'max_linear_acceleration_meters_per_second_squared': 5.0,
        'max_angular_acceleration_radians_per_second_squared': 7.5,
    }
    assert drivetrain.motion_limits('rc_pulse')['max_linear_velocity_meters_per_second'] == 1.37


def test_arm_only_machine_has_no_platform():
    assert load_machine('kinova-link-6').is_arm_only
    assert not load_machine('saburo').has_arm


def test_camera_queries():
    saburo = load_machine('saburo')
    assert saburo.has_zed_camera
    assert saburo.first_enabled_camera('zed_2').node_name == 'camera_0'
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
