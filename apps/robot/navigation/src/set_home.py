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
import pathlib
import re
import sys

import rclpy
from sensor_msgs.msg import NavSatFix

FIX_WAIT_SECONDS = 15.0


def current_fix(robot):
    rclpy.init()
    node = rclpy.create_node('set_home', namespace=f'/{robot}')
    received = []
    node.create_subscription(
        NavSatFix, 'sensors/gps_0/fix', received.append, 10)
    deadline = node.get_clock().now().nanoseconds * 1e-9 + FIX_WAIT_SECONDS
    while not received:
        if node.get_clock().now().nanoseconds * 1e-9 > deadline:
            sys.exit(f'no fix on /{robot}/sensors/gps_0/fix'
                     f' within {FIX_WAIT_SECONDS:.0f} seconds')
        rclpy.spin_once(node, timeout_sec=0.5)
    rclpy.shutdown()
    return received[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='taro')
    robot = parser.parse_args().robot
    fix = current_fix(robot)

    config_path = pathlib.Path(f'machines/{robot}/robot.yaml')
    config_text = config_path.read_text()
    updated_text, replacements = re.subn(
        r'(home:\n  latitude: )\S+(\n  longitude: )\S+',
        rf'\g<1>{fix.latitude}\g<2>{fix.longitude}',
        config_text)
    if replacements != 1:
        sys.exit(f'{config_path} has no home block to update')
    config_path.write_text(updated_text)
    print(f'{robot} home set to {fix.latitude}, {fix.longitude}'
          f' (fix status {fix.status.status})')


if __name__ == '__main__':
    main()
