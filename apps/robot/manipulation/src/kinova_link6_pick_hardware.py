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
import json
import pathlib
import threading
import time

from kortex_api.autogen.client_stubs.BaseClientRpc import BaseClient
from kortex_api.autogen.client_stubs.BaseCyclicClientRpc import (
    BaseCyclicClient)
from kortex_api.autogen.client_stubs.PluginClientRpc import PluginClient
from kortex_api.autogen.client_stubs.SessionClientRpc import SessionClient
from kortex_api.autogen.messages import Base_pb2, Plugin_pb2, Session_pb2
from kortex_api.autogen.messages.Common_pb2 import (
    ModeSelection, NotificationOptions, OPERATING_MODE_AUTO,
    OPERATING_MODE_MONITORED_STOP)
from kortex_api.exceptions.KServerException import KServerException
from kortex_api.MqttTransport import MqttTransport
from kortex_api.RouterClient import RouterClient
import yaml

POSES_FILE = pathlib.Path('machines/kinova-link-6/pick_poses.yaml')
GRIPPER_PLUGIN_NAMESPACE = 'robotiq_plugin'
GRIPPER_NAME = 'Gripper A'
GRIPPER_FULL_SCALE = 255
JOINT_COUNT = 6
MAX_JOINT_VELOCITY_DEGREES_PER_SECOND = 30.0
STOP_AT_WAYPOINT_BLENDING = 0.0
SESSION_INACTIVITY_TIMEOUT_MILLISECONDS = 60000
CONNECTION_INACTIVITY_TIMEOUT_MILLISECONDS = 2000
MODE_SETTLE_SECONDS = 1.0
EXECUTE_TIMEOUT_SECONDS = 60.0
GRIPPER_TIMEOUT_SECONDS = 15.0


def load_poses():
    if not POSES_FILE.exists():
        return {}
    with open(POSES_FILE) as poses_file:
        return yaml.safe_load(poses_file) or {}


def save_poses(poses):
    POSES_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(POSES_FILE, 'w') as poses_file:
        yaml.safe_dump(poses, poses_file, sort_keys=False)


class KinovaLink6Arm:
    def __init__(self, address, username, password,
                 joint_speed_degrees_per_second=MAX_JOINT_VELOCITY_DEGREES_PER_SECOND):
        self.joint_speed_degrees_per_second = joint_speed_degrees_per_second
        self.transport = MqttTransport()
        self.transport.connect(address)
        self.kortex_router = RouterClient(self.transport, errorCallback=None)
        session = Session_pb2.CreateSessionInfo()
        session.username = username
        session.password = password
        session.session_inactivity_timeout = SESSION_INACTIVITY_TIMEOUT_MILLISECONDS
        session.connection_inactivity_timeout = (
            CONNECTION_INACTIVITY_TIMEOUT_MILLISECONDS)
        self.session_client = SessionClient(self.kortex_router)
        self.session_client.CreateSession(session)
        self.base = BaseClient(self.kortex_router)
        self.base_cyclic = BaseCyclicClient(self.kortex_router)
        self.gripper_plugin = PluginClient(
            self.kortex_router, GRIPPER_PLUGIN_NAMESPACE)

    def close(self):
        self.session_client.CloseSession()
        self.transport.disconnect()

    def flush_stale_actions(self):
        try:
            self.base.StopAction()
        except KServerException:
            pass
        try:
            self.base.Stop()
        except KServerException:
            pass

    def joint_positions_degrees(self):
        feedback = self.base_cyclic.RefreshFeedback()
        return [actuator.position for actuator in feedback.actuators]

    def ensure_operating_mode(self, operating_mode):
        current = self.base.GetCurrentOperatingMode().operating_mode
        if current == operating_mode:
            return
        if current != OPERATING_MODE_MONITORED_STOP:
            self.base.SelectOperatingMode(
                ModeSelection(operating_mode=OPERATING_MODE_MONITORED_STOP))
            time.sleep(MODE_SETTLE_SECONDS)
        if operating_mode != OPERATING_MODE_MONITORED_STOP:
            self.base.SelectOperatingMode(
                ModeSelection(operating_mode=operating_mode))
            time.sleep(MODE_SETTLE_SECONDS)

    def move_through(self, waypoints_degrees):
        waypoint_list = Base_pb2.WaypointList()
        waypoint_list.use_optimal_blending = False
        for index, angles in enumerate(waypoints_degrees):
            waypoint = waypoint_list.waypoints.add()
            waypoint.name = f'waypoint_{index}'
            waypoint.angular_waypoint.angles.extend(angles)
            waypoint.angular_waypoint.maximum_velocities.extend(
                [self.joint_speed_degrees_per_second] * JOINT_COUNT)
            waypoint.angular_waypoint.blending = STOP_AT_WAYPOINT_BLENDING
        validation = self.base.ValidateWaypointList(waypoint_list)
        if validation.trajectory_error_report.trajectory_error_elements:
            raise RuntimeError(str(validation.trajectory_error_report))
        self.ensure_operating_mode(OPERATING_MODE_AUTO)
        finished = threading.Event()
        outcome = {}

        def on_action_event(notification):
            if notification.action_event == Base_pb2.ACTION_END:
                outcome['ok'] = True
                finished.set()
            elif notification.action_event == Base_pb2.ACTION_ABORT:
                outcome['ok'] = False
                outcome['error'] = str(notification)
                finished.set()

        subscription = self.base.OnNotificationActionTopic(
            on_action_event, Base_pb2.NotificationOptions())
        self.base.ExecuteWaypointTrajectory(waypoint_list)
        completed = finished.wait(EXECUTE_TIMEOUT_SECONDS)
        self.base.Unsubscribe(subscription)
        if not completed:
            raise RuntimeError(
                f'no trajectory completion within {EXECUTE_TIMEOUT_SECONDS}s')
        if not outcome.get('ok'):
            raise RuntimeError(outcome.get('error', 'trajectory aborted'))

    def run_gripper_action(self, identifier, parameters):
        action = Plugin_pb2.Action()
        action.handle.identifier = identifier
        action.serialization_type = Plugin_pb2.CONFIGURATION_TYPE_JSON
        action.input = json.dumps(parameters)
        finished = threading.Event()
        outcome = {}

        def on_action_event(notification):
            if notification.action_event == Plugin_pb2.ACTION_END:
                outcome['ok'] = True
                finished.set()
            elif notification.action_event in (
                    Plugin_pb2.ACTION_ABORT, Plugin_pb2.ACTION_CANCEL):
                outcome['ok'] = False
                outcome['error'] = str(notification)
                finished.set()

        subscription = self.gripper_plugin.OnNotificationActionTopic(
            on_action_event, NotificationOptions())
        self.gripper_plugin.StartAction(action)
        completed = finished.wait(GRIPPER_TIMEOUT_SECONDS)
        self.gripper_plugin.Unsubscribe(subscription)
        if not completed:
            raise RuntimeError(
                f"gripper '{identifier}' gave no completion within "
                f'{GRIPPER_TIMEOUT_SECONDS}s')
        if not outcome.get('ok'):
            raise RuntimeError(outcome.get('error', 'gripper action aborted'))

    def open_gripper(self, velocity):
        self.run_gripper_action('open', {
            'gripper': GRIPPER_NAME,
            'velocity': velocity,
            'force': GRIPPER_FULL_SCALE,
        })

    def close_gripper(self, force, velocity):
        self.run_gripper_action('close', {
            'gripper': GRIPPER_NAME,
            'velocity': velocity,
            'force': force,
        })


def record(arm, pose_name):
    poses = load_poses()
    poses[pose_name] = [round(angle, 3) for angle in arm.joint_positions_degrees()]
    save_poses(poses)
    print(f"recorded '{pose_name}': {poses[pose_name]}")


START_TOLERANCE_DEGREES = 15.0


def require_arm_at_home(arm, poses):
    offsets = [
        abs((actual - taught + 180.0) % 360.0 - 180.0)
        for taught, actual in zip(poses['home'], arm.joint_positions_degrees())]
    if max(offsets) > START_TOLERANCE_DEGREES:
        raise RuntimeError(
            f'arm is not at home (largest joint offset {max(offsets):.1f} '
            'deg). Hand-guide it back to home along the taught route first; '
            'runs only start from home so every motion is a taught leg.')


def load_required_poses(*pose_names):
    poses = load_poses()
    for pose_name in pose_names:
        if pose_name not in poses:
            raise RuntimeError(
                f"pose '{pose_name}' not recorded; run with "
                f'--record {pose_name} first')
    return poses


def approach_waypoints(poses, pose_name):
    waypoints = []
    index = 1
    while f'{pose_name}_{index}' in poses:
        waypoints.append(poses[f'{pose_name}_{index}'])
        index += 1
    hover_name = f'{pose_name}_hover'
    if hover_name in poses:
        waypoints.append(poses[hover_name])
    waypoints.append(poses[pose_name])
    return waypoints


def retreat_waypoints(poses, pose_name):
    return list(reversed(approach_waypoints(poses, pose_name)))[1:]


def run_pick(arm, grasp_pose, force, velocity):
    poses = load_required_poses('home', grasp_pose)
    require_arm_at_home(arm, poses)
    arm.ensure_operating_mode(OPERATING_MODE_AUTO)
    arm.flush_stale_actions()
    arm.open_gripper(velocity)
    arm.move_through([poses['home']])
    arm.move_through(approach_waypoints(poses, grasp_pose))
    arm.close_gripper(force, velocity)
    arm.move_through(retreat_waypoints(poses, grasp_pose) + [poses['home']])
    print('picked')


def run_place(arm, grasp_pose, velocity):
    poses = load_required_poses('home', grasp_pose)
    require_arm_at_home(arm, poses)
    arm.ensure_operating_mode(OPERATING_MODE_AUTO)
    arm.flush_stale_actions()
    arm.move_through([poses['home']])
    arm.move_through(approach_waypoints(poses, grasp_pose))
    arm.open_gripper(velocity)
    arm.move_through(retreat_waypoints(poses, grasp_pose) + [poses['home']])
    print('placed')


def run_deliver(arm, grasp_pose, destination, force, velocity):
    poses = load_required_poses('home', grasp_pose, destination)
    require_arm_at_home(arm, poses)
    arm.ensure_operating_mode(OPERATING_MODE_AUTO)
    arm.flush_stale_actions()
    arm.open_gripper(velocity)
    arm.move_through([poses['home']])
    arm.move_through(approach_waypoints(poses, grasp_pose))
    arm.close_gripper(force, velocity)
    arm.move_through(retreat_waypoints(poses, grasp_pose) + [poses['home']])
    arm.move_through(approach_waypoints(poses, destination))
    arm.open_gripper(velocity)
    arm.move_through(retreat_waypoints(poses, destination) + [poses['home']])
    print(f'delivered {grasp_pose} to {destination}')


def run_tour(arm, stops, force, velocity):
    poses = load_required_poses('home', *stops)
    require_arm_at_home(arm, poses)
    arm.ensure_operating_mode(OPERATING_MODE_AUTO)
    arm.flush_stale_actions()
    arm.open_gripper(velocity)
    arm.move_through([poses['home']])
    arm.move_through(approach_waypoints(poses, stops[0]))
    arm.close_gripper(force, velocity)
    for index, stop in enumerate(stops[1:], start=1):
        arm.move_through(
            retreat_waypoints(poses, stops[index - 1])
            + approach_waypoints(poses, stop))
        arm.open_gripper(velocity)
        if index < len(stops) - 1:
            arm.close_gripper(force, velocity)
    arm.move_through(retreat_waypoints(poses, stops[-1]) + [poses['home']])
    print('toured ' + ' -> '.join(stops))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot-ip', default='192.168.1.10')
    parser.add_argument('--robot-username', default='admin')
    parser.add_argument('--robot-password', default='admin')
    parser.add_argument('--record')
    parser.add_argument('--place', action='store_true')
    parser.add_argument('--deliver', action='store_true')
    parser.add_argument('--grasp-pose', default='grasp')
    parser.add_argument('--destination', default='dropoff')
    parser.add_argument('--tour', nargs='+')
    parser.add_argument('--force', type=int, default=10)
    parser.add_argument('--velocity', type=int, default=50)
    parser.add_argument('--joint-speed', type=float,
                        default=MAX_JOINT_VELOCITY_DEGREES_PER_SECOND)
    arguments = parser.parse_args()
    arm = KinovaLink6Arm(arguments.robot_ip, arguments.robot_username,
                         arguments.robot_password,
                         joint_speed_degrees_per_second=arguments.joint_speed)
    try:
        if arguments.record:
            record(arm, arguments.record)
        elif arguments.place:
            run_place(arm, arguments.grasp_pose, arguments.velocity)
        elif arguments.tour:
            run_tour(arm, arguments.tour, arguments.force,
                     arguments.velocity)
        elif arguments.deliver:
            run_deliver(arm, arguments.grasp_pose, arguments.destination,
                        arguments.force, arguments.velocity)
        else:
            run_pick(arm, arguments.grasp_pose, arguments.force,
                     arguments.velocity)
    finally:
        arm.close()


if __name__ == '__main__':
    main()
