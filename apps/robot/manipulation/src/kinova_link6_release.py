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

from action_msgs.msg import GoalStatus
from control_msgs.action import FollowJointTrajectory, GripperCommand
from moveit_msgs.msg import AttachedCollisionObject, CollisionObject
from moveit_msgs.srv import ApplyPlanningScene
import rclpy
from rclpy.action import ActionClient
from rclpy.duration import Duration
from rclpy.node import Node
from trajectory_msgs.msg import JointTrajectoryPoint
import yaml

ARM_JOINTS = ['joint_1', 'joint_2', 'joint_3', 'joint_4', 'joint_5', 'joint_6']
GRIPPER_OPEN_RADIANS = 0.0
GRIPPER_MAX_EFFORT = 5.0
DEMONSTRATION_MOVE_DURATION_SECONDS = 4
SERVER_TIMEOUT_SECONDS = 10.0


def demonstration_joint_positions(robot):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        machine = yaml.safe_load(machine_file)
    return machine['manipulation']['demonstration_joint_positions']


def run_action(node, action_type, action_name, goal):
    client = ActionClient(node, action_type, action_name)
    if not client.wait_for_server(timeout_sec=SERVER_TIMEOUT_SECONDS):
        raise RuntimeError(f'{action_name} server unavailable')
    goal_future = client.send_goal_async(goal)
    rclpy.spin_until_future_complete(node, goal_future)
    goal_handle = goal_future.result()
    if not goal_handle.accepted:
        raise RuntimeError(f'{action_name} rejected the goal')
    result_future = goal_handle.get_result_async()
    rclpy.spin_until_future_complete(node, result_future)
    if result_future.result().status != GoalStatus.STATUS_SUCCEEDED:
        raise RuntimeError(
            f'{action_name} ended with status '
            f'{result_future.result().status}')


def open_gripper(node):
    goal = GripperCommand.Goal()
    goal.command.position = GRIPPER_OPEN_RADIANS
    goal.command.max_effort = GRIPPER_MAX_EFFORT
    run_action(node, GripperCommand,
               'robotiq_gripper_controller/gripper_cmd', goal)


def remove_object(node, object_id):
    scene_applier = node.create_client(
        ApplyPlanningScene, 'apply_planning_scene')
    if not scene_applier.wait_for_service(timeout_sec=SERVER_TIMEOUT_SECONDS):
        raise RuntimeError('apply_planning_scene service unavailable')
    detach_from_robot = AttachedCollisionObject()
    detach_from_robot.object.id = object_id
    detach_from_robot.object.operation = CollisionObject.REMOVE
    remove_from_world = CollisionObject()
    remove_from_world.id = object_id
    remove_from_world.operation = CollisionObject.REMOVE
    request = ApplyPlanningScene.Request()
    request.scene.is_diff = True
    request.scene.robot_state.is_diff = True
    request.scene.robot_state.attached_collision_objects.append(
        detach_from_robot)
    request.scene.world.collision_objects.append(remove_from_world)
    future = scene_applier.call_async(request)
    rclpy.spin_until_future_complete(node, future)


def move_to_demonstration_pose(node, positions):
    goal = FollowJointTrajectory.Goal()
    goal.trajectory.joint_names = ARM_JOINTS
    point = JointTrajectoryPoint()
    point.positions = [float(position) for position in positions]
    point.time_from_start = Duration(
        seconds=DEMONSTRATION_MOVE_DURATION_SECONDS).to_msg()
    goal.trajectory.points = [point]
    run_action(node, FollowJointTrajectory,
               'joint_trajectory_controller/follow_joint_trajectory', goal)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='kinova-link-6')
    parser.add_argument('--object', default='apple')
    arguments = parser.parse_args()
    rclpy.init()
    node = Node('release_task')
    open_gripper(node)
    remove_object(node, arguments.object)
    move_to_demonstration_pose(
        node, demonstration_joint_positions(arguments.robot))
    print(f"released '{arguments.object}'")


if __name__ == '__main__':
    main()
