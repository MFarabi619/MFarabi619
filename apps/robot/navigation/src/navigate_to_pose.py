#!/usr/bin/env python3

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


import argparse
import os
from pathlib import Path

from robot_boot.zenoh_router import connect_to_zenoh_router
from robot_machines.machine import load_machine

RVIZ_EXECUTABLE = 'rviz2'
RVIZ_CONFIGURATION_PATH = Path(__file__).resolve().parents[1] / 'config' / 'navigate_to_pose.rviz'


def rviz_command(namespace):
    return [
        RVIZ_EXECUTABLE, '-d', str(RVIZ_CONFIGURATION_PATH),
        '--ros-args',
        '-r', f'__ns:=/{namespace}',
        '-r', '/tf:=tf',
        '-r', '/tf_static:=tf_static',
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='jiro')
    robot = parser.parse_args().robot
    namespace = load_machine(robot).namespace
    connect_to_zenoh_router(robot)
    os.execvp(RVIZ_EXECUTABLE, rviz_command(namespace))


if __name__ == '__main__':
    main()
