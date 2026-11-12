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
from control_msgs.action import GripperCommand
from geometry_msgs.msg import Point, Pose, PoseStamped, Quaternion
from moveit_msgs.action import MoveGroup
from moveit_msgs.msg import (AttachedCollisionObject, CollisionObject,
                             Constraints, JointConstraint,
                             OrientationConstraint, PositionConstraint)
from moveit_msgs.srv import ApplyPlanningScene
from mujoco_ros2_control_msgs.msg import FreeJointStateArray
import numpy
import rclpy
from rclpy.action import ActionClient
from rclpy.node import Node
from shape_msgs.msg import SolidPrimitive
from tf2_ros import Buffer, TransformListener
from trimesh import transformations

ARM_JOINTS = ['joint_1', 'joint_2', 'joint_3', 'joint_4', 'joint_5', 'joint_6']
HOME_POSITIONS_RADIANS = [0.0] * len(ARM_JOINTS)
GRIPPER_OPEN_RADIANS = 0.0
GRIPPER_MAX_EFFORT = 5.0
SERVER_TIMEOUT_SECONDS = 10.0
MESSAGE_TIMEOUT_SECONDS = 10.0
PLANNING_GROUP = 'arm'
END_EFFECTOR_LINK = 'end_effector_link'
BASE_FRAME = 'base_link'
RETREAT_METERS = 0.10
RELEASE_CLEARANCE_METERS = 0.008
POSITION_TOLERANCE_METERS = 0.005
ORIENTATION_TOLERANCE_RADIANS = 0.05
JOINT_TOLERANCE_RADIANS = 0.01
MAX_VELOCITY_SCALING_FACTOR = 0.5
MAX_ACCELERATION_SCALING_FACTOR = 0.5
PLANNING_TIME_SECONDS = 5.0
PLANNING_ATTEMPTS = 3


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


def wait_for_message(node, message_type, topic, predicate):
    received = []

    def on_message(message):
        if predicate(message):
            received.append(message)

    subscription = node.create_subscription(message_type, topic, on_message, 10)
    deadline = node.get_clock().now().nanoseconds / 1e9 + MESSAGE_TIMEOUT_SECONDS
    while not received:
        rclpy.spin_once(node, timeout_sec=0.1)
        if node.get_clock().now().nanoseconds / 1e9 > deadline:
            raise RuntimeError(f'no message on {topic}')
    node.destroy_subscription(subscription)
    return received[0]


def pre_attach_pose(node, object_id):
    message = wait_for_message(
        node, PoseStamped, f'pre_attach_pose/{object_id}',
        lambda message: True)
    return message.pose


def current_free_body_pose(node, object_id):
    message = wait_for_message(
        node, FreeJointStateArray,
        'free_joint_state_publisher/free_joint_states',
        lambda message: any(
            state.name == object_id for state in message.free_joints))
    for state in message.free_joints:
        if state.name == object_id:
            return state.pose.pose
    raise RuntimeError(f'{object_id} missing from free joint states')


def matrix_from_pose(pose):
    matrix = transformations.quaternion_matrix([
        pose.orientation.w, pose.orientation.x,
        pose.orientation.y, pose.orientation.z])
    matrix[:3, 3] = [pose.position.x, pose.position.y, pose.position.z]
    return matrix


def pose_from_matrix(matrix):
    w, x, y, z = transformations.quaternion_from_matrix(matrix)
    return Pose(
        position=Point(
            x=float(matrix[0, 3]), y=float(matrix[1, 3]),
            z=float(matrix[2, 3])),
        orientation=Quaternion(x=float(x), y=float(y), z=float(z), w=float(w)))


def end_effector_matrix(node, tf_buffer):
    deadline = node.get_clock().now().nanoseconds / 1e9 + MESSAGE_TIMEOUT_SECONDS
    while not tf_buffer.can_transform(
            BASE_FRAME, END_EFFECTOR_LINK, rclpy.time.Time()):
        rclpy.spin_once(node, timeout_sec=0.1)
        if node.get_clock().now().nanoseconds / 1e9 > deadline:
            raise RuntimeError(
                f'no transform {BASE_FRAME} -> {END_EFFECTOR_LINK}')
    transform = tf_buffer.lookup_transform(
        BASE_FRAME, END_EFFECTOR_LINK, rclpy.time.Time()).transform
    return matrix_from_pose(Pose(
        position=Point(
            x=transform.translation.x, y=transform.translation.y,
            z=transform.translation.z),
        orientation=transform.rotation))


def move_group_goal(constraints):
    goal = MoveGroup.Goal()
    goal.request.group_name = PLANNING_GROUP
    goal.request.goal_constraints = [constraints]
    goal.request.max_velocity_scaling_factor = MAX_VELOCITY_SCALING_FACTOR
    goal.request.max_acceleration_scaling_factor = MAX_ACCELERATION_SCALING_FACTOR
    goal.request.allowed_planning_time = PLANNING_TIME_SECONDS
    goal.request.num_planning_attempts = PLANNING_ATTEMPTS
    goal.planning_options.plan_only = False
    return goal


def move_to_pose(node, pose):
    region = SolidPrimitive(
        type=SolidPrimitive.SPHERE, dimensions=[POSITION_TOLERANCE_METERS])
    position = PositionConstraint()
    position.header.frame_id = BASE_FRAME
    position.link_name = END_EFFECTOR_LINK
    position.constraint_region.primitives.append(region)
    position.constraint_region.primitive_poses.append(
        Pose(position=pose.position))
    position.weight = 1.0
    orientation = OrientationConstraint()
    orientation.header.frame_id = BASE_FRAME
    orientation.link_name = END_EFFECTOR_LINK
    orientation.orientation = pose.orientation
    orientation.absolute_x_axis_tolerance = ORIENTATION_TOLERANCE_RADIANS
    orientation.absolute_y_axis_tolerance = ORIENTATION_TOLERANCE_RADIANS
    orientation.absolute_z_axis_tolerance = ORIENTATION_TOLERANCE_RADIANS
    orientation.weight = 1.0
    constraints = Constraints(
        position_constraints=[position],
        orientation_constraints=[orientation])
    run_action(node, MoveGroup, 'move_action', move_group_goal(constraints))


def move_to_joint_positions(node, positions):
    constraints = Constraints(joint_constraints=[
        JointConstraint(
            joint_name=joint_name, position=float(position),
            tolerance_above=JOINT_TOLERANCE_RADIANS,
            tolerance_below=JOINT_TOLERANCE_RADIANS, weight=1.0)
        for joint_name, position in zip(ARM_JOINTS, positions)])
    run_action(node, MoveGroup, 'move_action', move_group_goal(constraints))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target_object', default='apple')
    arguments = parser.parse_args()
    rclpy.init()
    node = Node('kinova_link6_place')
    tf_buffer = Buffer()
    TransformListener(tf_buffer, node)

    original = matrix_from_pose(pre_attach_pose(node, arguments.target_object))
    original[2, 3] += RELEASE_CLEARANCE_METERS
    held = matrix_from_pose(current_free_body_pose(node, arguments.target_object))
    end_effector = end_effector_matrix(node, tf_buffer)
    place_target = original @ numpy.linalg.inv(held) @ end_effector
    move_to_pose(node, pose_from_matrix(place_target))

    open_gripper(node)
    remove_object(node, arguments.target_object)

    retreat_target = place_target.copy()
    retreat_target[2, 3] += RETREAT_METERS
    move_to_pose(node, pose_from_matrix(retreat_target))
    move_to_joint_positions(node, HOME_POSITIONS_RADIANS)
    print(f"placed '{arguments.target_object}'")


if __name__ == '__main__':
    main()
