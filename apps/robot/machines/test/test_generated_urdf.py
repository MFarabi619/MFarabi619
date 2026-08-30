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
import xml.etree.ElementTree as ElementTree

import pytest
import yaml

ROBOT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
URDF_DECIMALS = 4
PLACEMENT_TOLERANCE_M = 10.0 ** -URDF_DECIMALS


def machine_names():
    return sorted(
        os.path.basename(os.path.dirname(path))
        for path in glob.glob(os.path.join(ROBOT_ROOT, 'machines', '*', 'robot.yaml')))


def configured_cameras(machine):
    config = yaml.safe_load(
        open(os.path.join(ROBOT_ROOT, 'machines', machine, 'robot.yaml')))
    cameras = (config.get('sensors') or {}).get('camera') or []
    return [camera for camera in cameras if camera.get('launch_enabled', True)]


def joint_origins(urdf_path):
    origins = {}
    for joint in ElementTree.parse(urdf_path).getroot().iter('joint'):
        child = joint.find('child')
        origin = joint.find('origin')
        if child is None or origin is None:
            continue
        origins[child.get('link')] = [
            float(value) for value in origin.get('xyz', '0 0 0').split()]
    return origins


@pytest.mark.parametrize('machine', machine_names())
def test_every_machine_has_a_generated_urdf(machine):
    for urdf in ('robot.urdf', 'robot.sim.urdf'):
        path = os.path.join(ROBOT_ROOT, 'mech', 'urdf', machine, urdf)
        assert os.path.isfile(path), f'{machine}/{urdf} missing — rerun the assembly generator'


@pytest.mark.parametrize('machine', machine_names())
def test_camera_joint_matches_the_configured_placement(machine):
    """robot.yaml owns sensor placement, so a stale URDF must not pass silently."""
    cameras = configured_cameras(machine)
    if not cameras:
        return
    for urdf in ('robot.urdf', 'robot.sim.urdf'):
        origins = joint_origins(os.path.join(ROBOT_ROOT, 'mech', 'urdf', machine, urdf))
        for index, camera in enumerate(cameras):
            link = f'camera_{index}_link'
            assert link in origins, f'{machine}/{urdf} has no {link}'
            for axis, configured in enumerate(camera.get('xyz', [0.0, 0.0, 0.0])):
                assert origins[link][axis] == pytest.approx(
                    configured, abs=PLACEMENT_TOLERANCE_M), (
                        f'{machine}/{urdf} {link} disagrees with robot.yaml'
                        ' — rerun the assembly generator')
