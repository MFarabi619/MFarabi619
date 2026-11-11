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


import os
import shlex
import subprocess

ROBOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
STARTUP_GRACE_S = 10
LAUNCH_FAILURES = (
    'unexpected argument',
    'No such file or directory',
    'Invalid configuration',
    'error: the argument',
    'failed to solve',
    'Caught exception',
)


def spawned_output(command):
    process = subprocess.Popen(
        shlex.split(command), cwd=ROBOT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        process.wait(timeout=STARTUP_GRACE_S)
        alive = False
    except subprocess.TimeoutExpired:
        alive = True
    process.terminate()
    try:
        output, _ = process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate()
    return alive, output


def test_behavior_server_launches_and_reaches_zenoh():
    executable = os.path.join(
        ROBOT_DIR, '.pixi', 'envs', 'default', 'lib',
        'nav2_behaviors', 'behavior_server')
    alive, output = spawned_output(
        f'{executable} --ros-args -r __node:=behavior_server'
        ' --params-file navigation/config/behaviors.yaml'
        ' -p use_sim_time:=true')
    for failure in LAUNCH_FAILURES:
        assert failure not in output, output[-2000:]
    assert alive or 'localhost:7447' in output, output[-2000:]
