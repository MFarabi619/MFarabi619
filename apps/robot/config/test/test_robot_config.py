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


from pathlib import Path

import pytest

from robot_config.robot_config import RobotConfig

ROBOTS_PATH = Path(__file__).resolve().parents[1] / 'robots'
SAMPLES = sorted(ROBOTS_PATH.glob('*/robot.yaml'))


def test_samples_are_present():
    assert SAMPLES, f'no robot.yaml samples under {ROBOTS_PATH}'


@pytest.mark.parametrize('sample', SAMPLES, ids=lambda path: path.parent.name)
def test_robot_yaml_parses(sample):
    config = RobotConfig(str(sample))
    assert str(config.serial_number).startswith('robot-')
    assert isinstance(config.version, int)
