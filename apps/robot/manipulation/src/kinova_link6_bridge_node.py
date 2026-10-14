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


import json
import math
import socket
import threading
import xml.etree.ElementTree as ElementTree

from control_msgs.action import FollowJointTrajectory, GripperCommand
from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.action import ActionServer
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile
from sensor_msgs.msg import JointState
from std_msgs.msg import String

BRIDGE_HOST = '127.0.0.1'
BRIDGE_PORT = 10900
ARM_JOINTS = ['joint_1', 'joint_2', 'joint_3',
              'joint_4', 'joint_5', 'joint_6']
GRIPPER_JOINT = 'robotiq_85_left_knuckle_joint'
STATE_RATE_HZ = 20.0
MAX_WAYPOINTS = 30
STATE_SOCKET_TIMEOUT_SECONDS = 2.0
TELEOP_LINEAR_GAIN = 0.1
TELEOP_ANGULAR_GAIN_DEG_PER_RADIAN = 20.0
TELEOP_MAX_LINEAR_METERS_PER_SECOND = 0.25
TELEOP_MAX_ANGULAR_DEG_PER_SECOND = 45.0


def clamp(value, limit):
    return max(-limit, min(limit, value))


class BridgeConnection:
    def __init__(self, timeout_seconds):
        self.timeout_seconds = timeout_seconds
        self.lock = threading.Lock()
        self.connection = None
        self.reader = None

    def request(self, payload):
        with self.lock:
            try:
                if self.connection is None:
                    self.connection = socket.create_connection(
                        (BRIDGE_HOST, BRIDGE_PORT),
                        timeout=self.timeout_seconds)
                    self.reader = self.connection.makefile('r')
                self.connection.sendall((json.dumps(payload) + '\n').encode())
                line = self.reader.readline()
                if not line:
                    raise ConnectionError('bridge closed the connection')
                return json.loads(line)
            except Exception:
                if self.connection is not None:
                    self.connection.close()
                self.connection = None
                self.reader = None
                raise


class KinovaLink6BridgeNode(Node):
    def __init__(self):
        super().__init__('kinova_link6_bridge')
        self.state_connection = BridgeConnection(STATE_SOCKET_TIMEOUT_SECONDS)
        self.motion_connection = BridgeConnection(None)
        self.mimic_joints = []
        self.passive_joints = []
        self.commanded_gripper_position = 0.0
        callback_group = ReentrantCallbackGroup()
        self.joint_state_publisher = self.create_publisher(
            JointState, 'joint_states', 10)
        self.teleop_connection = BridgeConnection(STATE_SOCKET_TIMEOUT_SECONDS)
        self.create_subscription(
            String, 'robot_description', self.on_robot_description,
            QoSProfile(depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL),
            callback_group=callback_group)
        self.create_subscription(
            TwistStamped, 'arm_teleop/cmd_vel', self.on_teleop_twist, 10,
            callback_group=callback_group)
        self.create_timer(
            1.0 / STATE_RATE_HZ, self.publish_joint_states,
            callback_group=callback_group)
        ActionServer(
            self, FollowJointTrajectory,
            'joint_trajectory_controller/follow_joint_trajectory',
            self.execute_trajectory, callback_group=callback_group)
        ActionServer(
            self, GripperCommand, 'robotiq_gripper_controller/gripper_cmd',
            self.execute_gripper_command, callback_group=callback_group)

    def on_robot_description(self, message):
        mimic_joints = []
        passive_joints = []
        for joint in ElementTree.fromstring(message.data).findall('joint'):
            if joint.get('type') == 'fixed':
                continue
            name = joint.get('name')
            if name in ARM_JOINTS or name == GRIPPER_JOINT:
                continue
            mimic = joint.find('mimic')
            if mimic is not None:
                mimic_joints.append((
                    name, mimic.get('joint'),
                    float(mimic.get('multiplier', 1.0)),
                    float(mimic.get('offset', 0.0))))
            else:
                passive_joints.append(name)
        self.mimic_joints = mimic_joints
        self.passive_joints = passive_joints

    def on_teleop_twist(self, message):
        twist = message.twist
        linear = [
            clamp(axis * TELEOP_LINEAR_GAIN,
                  TELEOP_MAX_LINEAR_METERS_PER_SECOND)
            for axis in (twist.linear.x, twist.linear.y, twist.linear.z)]
        angular = [
            clamp(axis * TELEOP_ANGULAR_GAIN_DEG_PER_RADIAN,
                  TELEOP_MAX_ANGULAR_DEG_PER_SECOND)
            for axis in (twist.angular.x, twist.angular.y, twist.angular.z)]
        try:
            self.teleop_connection.request(
                {'op': 'twist', 'linear': linear, 'angular': angular})
        except Exception as error:
            self.get_logger().warning(
                f'teleop twist failed: {error}', throttle_duration_sec=5.0)

    def publish_joint_states(self):
        try:
            state = self.state_connection.request({'op': 'state'})
        except Exception as error:
            self.get_logger().warning(
                f'bridge unreachable: {error}', throttle_duration_sec=5.0)
            return
        positions = {name: math.radians(position_deg) for name, position_deg
                     in zip(ARM_JOINTS, state['positions_deg'])}
        velocities = {
            name: math.radians(velocity_deg_per_second)
            for name, velocity_deg_per_second
            in zip(ARM_JOINTS, state['velocities_deg'])}
        positions[GRIPPER_JOINT] = self.commanded_gripper_position
        for name in self.passive_joints:
            positions[name] = 0.0
        for name, source, multiplier, offset in self.mimic_joints:
            positions[name] = positions.get(source, 0.0) * multiplier + offset
        message = JointState()
        message.header.stamp = self.get_clock().now().to_msg()
        message.name = list(positions)
        message.position = [positions[name] for name in message.name]
        message.velocity = [velocities.get(name, 0.0) for name in message.name]
        self.joint_state_publisher.publish(message)

    def execute_trajectory(self, goal_handle):
        result = FollowJointTrajectory.Result()
        trajectory = goal_handle.request.trajectory
        try:
            arm_joint_indices = [trajectory.joint_names.index(name)
                                 for name in ARM_JOINTS]
        except ValueError:
            goal_handle.abort()
            result.error_code = FollowJointTrajectory.Result.INVALID_JOINTS
            result.error_string = f'expected joints {ARM_JOINTS}, got {list(trajectory.joint_names)}'
            return result
        points = trajectory.points
        stride = max(1, math.ceil(len(points) / MAX_WAYPOINTS))
        kept_points = list(points[::stride])
        if kept_points[-1] is not points[-1]:
            kept_points.append(points[-1])
        waypoints_deg = [
            [math.degrees(point.positions[index])
             for index in arm_joint_indices]
            for point in kept_points]
        self.get_logger().info(
            f'executing trajectory: {len(points)} points '
            f'as {len(kept_points)} waypoints')
        try:
            reply = self.motion_connection.request(
                {'op': 'execute', 'waypoints_deg': waypoints_deg})
        except Exception as error:
            reply = {'ok': False, 'error': str(error)}
        if reply.get('ok'):
            goal_handle.succeed()
            result.error_code = FollowJointTrajectory.Result.SUCCESSFUL
        else:
            goal_handle.abort()
            result.error_code = FollowJointTrajectory.Result.PATH_TOLERANCE_VIOLATED
            result.error_string = reply.get('error', '')
            self.get_logger().error(f'trajectory failed: {result.error_string}')
        return result

    def execute_gripper_command(self, goal_handle):
        self.commanded_gripper_position = goal_handle.request.command.position
        self.get_logger().warning(
            'gripper command is display-only, hardware gripper not wired yet')
        goal_handle.succeed()
        result = GripperCommand.Result()
        result.position = self.commanded_gripper_position
        result.reached_goal = True
        return result


def main():
    rclpy.init()
    node = KinovaLink6BridgeNode()
    executor = MultiThreadedExecutor(num_threads=4)
    try:
        rclpy.spin(node, executor)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
