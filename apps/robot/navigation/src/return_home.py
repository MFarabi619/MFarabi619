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

from geographic_msgs.msg import GeoPose
from nav2_simple_commander.robot_navigator import BasicNavigator
import rclpy
import yaml


def home_coordinate(robot):
    with open(f'machines/{robot}/robot.yaml') as file:
        return yaml.safe_load(file)['home']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='taro')
    robot = parser.parse_args().robot
    home = home_coordinate(robot)

    rclpy.init()
    navigator = BasicNavigator(namespace=f'/{robot}')
    goal = GeoPose()
    goal.position.latitude = home['latitude']
    goal.position.longitude = home['longitude']
    goal.orientation.w = 1.0
    navigator.followGpsWaypoints([goal])
    try:
        while not navigator.isTaskComplete():
            pass
        print(f'return home: {navigator.getResult().name}')
    except KeyboardInterrupt:
        navigator.cancelTask()
        print('return home: CANCELED')
    rclpy.shutdown()


if __name__ == '__main__':
    main()
