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


import math

from geometry_msgs.msg import Point
from nav2_msgs.action import DriveOnHeading, Spin
import py_trees
import py_trees_ros
import rclpy
from robot_platform_msgs.action import FollowRow

ROBOT_LENGTH_METERS = 1.15
ROBOT_WIDTH_METERS = 1.27
PIVOT_RADIUS_METERS = math.hypot(ROBOT_LENGTH_METERS, ROBOT_WIDTH_METERS) / 2.0
ROW_LOST_UNCERTAINTY_METERS = 0.7
HEADLAND_CLEARANCE_METERS = (
    ROBOT_LENGTH_METERS + PIVOT_RADIUS_METERS + ROW_LOST_UNCERTAINTY_METERS)
CLEAR_SPEED_METERS_PER_SECOND = 0.3
TURN_SHORTFALL_RADIANS = 0.05
TURN_TARGET_RADIANS = math.pi - TURN_SHORTFALL_RADIANS
TIME_ALLOWANCE_SECONDS = 60
TICK_PERIOD_MILLISECONDS = 100.0


def time_allowance():
    return rclpy.duration.Duration(seconds=TIME_ALLOWANCE_SECONDS).to_msg()


def follow_row_goal():
    return FollowRow.Goal()


def clear_headland_goal():
    goal = DriveOnHeading.Goal()
    goal.target = Point(x=HEADLAND_CLEARANCE_METERS)
    goal.speed = CLEAR_SPEED_METERS_PER_SECOND
    goal.time_allowance = time_allowance()
    return goal


def turn_around_goal():
    goal = Spin.Goal()
    goal.target_yaw = TURN_TARGET_RADIANS
    goal.time_allowance = time_allowance()
    return goal


def acquire_and_follow_row():
    return py_trees.decorators.FailureIsRunning(
        'acquire_and_follow_row',
        py_trees_ros.action_clients.FromConstant(
            name='follow_row', action_type=FollowRow,
            action_name='follow_row', action_goal=follow_row_goal()))


def shuttle_pass():
    return py_trees.composites.Sequence('shuttle_pass', memory=True, children=[
        acquire_and_follow_row(),
        py_trees_ros.action_clients.FromConstant(
            name='clear_headland', action_type=DriveOnHeading,
            action_name='drive_on_heading', action_goal=clear_headland_goal()),
        py_trees_ros.action_clients.FromConstant(
            name='turn_around', action_type=Spin,
            action_name='spin', action_goal=turn_around_goal()),
    ])


def mission():
    return py_trees.decorators.Repeat(
        'row_shuttle', shuttle_pass(), num_success=-1)


def halt_when_failed(tree):
    if tree.root.status == py_trees.common.Status.FAILURE:
        tree.timer.cancel()


def main():
    rclpy.init()
    tree = py_trees_ros.trees.BehaviourTree(mission())
    tree.setup(node_name='row_shuttle')
    tree.add_post_tick_handler(halt_when_failed)
    tree.tick_tock(period_ms=TICK_PERIOD_MILLISECONDS)
    try:
        rclpy.spin(tree.node)
    except KeyboardInterrupt:
        pass
    finally:
        tree.shutdown()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
