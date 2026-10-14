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
import socketserver
import threading
import time

from kortex_api.autogen.client_stubs.BaseClientRpc import BaseClient
from kortex_api.autogen.client_stubs.BaseCyclicClientRpc import BaseCyclicClient
from kortex_api.autogen.client_stubs.SessionClientRpc import SessionClient
from kortex_api.autogen.messages import Base_pb2, Session_pb2
from kortex_api.autogen.messages.Common_pb2 import (
    OPERATING_MODE_AUTO, OPERATING_MODE_JOG_MANUAL,
    OPERATING_MODE_MONITORED_STOP, ModeSelection)
from kortex_api.MqttTransport import MqttTransport
from kortex_api.RouterClient import RouterClient

BRIDGE_HOST = '127.0.0.1'
BRIDGE_PORT = 10900
JOINT_COUNT = 6
EXECUTE_TIMEOUT_SECONDS = 300.0
MODE_SETTLE_SECONDS = 2.0
SESSION_INACTIVITY_TIMEOUT_MS = 60000
CONNECTION_INACTIVITY_TIMEOUT_MS = 2000
MAX_JOINT_VELOCITY_DEG_PER_SECOND = 60.0
SMOOTH_BLENDING = 1.0
STOP_AT_WAYPOINT_BLENDING = 0.0
TWIST_WATCHDOG_SECONDS = 0.7
TWIST_WATCHDOG_POLL_SECONDS = 0.1
TWIST_DURATION_SECONDS = 1

parser = argparse.ArgumentParser()
parser.add_argument('--robot-ip', default='192.168.1.10')
parser.add_argument('--robot-username', default='admin')
parser.add_argument('--robot-password', default='admin')
args = parser.parse_args()

transport = MqttTransport()
transport.connect(args.robot_ip)
router = RouterClient(transport, errorCallback=None)

session_info = Session_pb2.CreateSessionInfo()
session_info.username = args.robot_username
session_info.password = args.robot_password
session_info.session_inactivity_timeout = SESSION_INACTIVITY_TIMEOUT_MS
session_info.connection_inactivity_timeout = CONNECTION_INACTIVITY_TIMEOUT_MS
session_client = SessionClient(router)
session_client.CreateSession(session_info)

base = BaseClient(router)
base_cyclic = BaseCyclicClient(router)
motion_lock = threading.Lock()
twist_lock = threading.Lock()
twist_deadline = None


def read_state():
    feedback = base_cyclic.RefreshFeedback()
    return {
        'positions_deg': [actuator.position for actuator in feedback.actuators],
        'velocities_deg': [actuator.velocity for actuator in feedback.actuators],
    }


def ensure_operating_mode(operating_mode):
    current_operating_mode = base.GetCurrentOperatingMode().operating_mode
    if current_operating_mode == operating_mode:
        return
    if current_operating_mode != OPERATING_MODE_MONITORED_STOP:
        base.SelectOperatingMode(
            ModeSelection(operating_mode=OPERATING_MODE_MONITORED_STOP))
        time.sleep(MODE_SETTLE_SECONDS)
    if operating_mode != OPERATING_MODE_MONITORED_STOP:
        base.SelectOperatingMode(
            ModeSelection(operating_mode=operating_mode))
        time.sleep(MODE_SETTLE_SECONDS)


def send_twist(linear, angular):
    command = Base_pb2.TwistCommand()
    command.reference_frame = Base_pb2.CARTESIAN_REFERENCE_FRAME_BASE
    command.duration = TWIST_DURATION_SECONDS
    command.twist.linear_x, command.twist.linear_y, command.twist.linear_z = linear
    command.twist.angular_x, command.twist.angular_y, command.twist.angular_z = angular
    base.SendTwistCommand(command)


def apply_twist(linear, angular):
    global twist_deadline
    ensure_operating_mode(OPERATING_MODE_JOG_MANUAL)
    with twist_lock:
        send_twist(linear, angular)
        if any(linear) or any(angular):
            twist_deadline = time.monotonic() + TWIST_WATCHDOG_SECONDS
        else:
            twist_deadline = None
    return {'ok': True}


def run_twist_watchdog():
    global twist_deadline
    while True:
        time.sleep(TWIST_WATCHDOG_POLL_SECONDS)
        with twist_lock:
            if twist_deadline is not None and time.monotonic() > twist_deadline:
                send_twist((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
                twist_deadline = None


def execute_waypoints(waypoints_deg):
    waypoint_list = Base_pb2.WaypointList()
    waypoint_list.use_optimal_blending = True
    for index, angles in enumerate(waypoints_deg):
        waypoint = waypoint_list.waypoints.add()
        waypoint.name = f'waypoint_{index}'
        waypoint.angular_waypoint.angles.extend(angles)
        waypoint.angular_waypoint.maximum_velocities.extend(
            [MAX_JOINT_VELOCITY_DEG_PER_SECOND] * JOINT_COUNT)
        waypoint.angular_waypoint.blending = (
            STOP_AT_WAYPOINT_BLENDING if index == len(waypoints_deg) - 1
            else SMOOTH_BLENDING)
    validation = base.ValidateWaypointList(waypoint_list)
    if validation.trajectory_error_report.trajectory_error_elements:
        return {'ok': False, 'error': str(validation.trajectory_error_report)}

    ensure_operating_mode(OPERATING_MODE_AUTO)
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

    subscription = base.OnNotificationActionTopic(
        on_action_event, Base_pb2.NotificationOptions())
    base.ExecuteWaypointTrajectory(waypoint_list)
    completed = finished.wait(EXECUTE_TIMEOUT_SECONDS)
    base.Unsubscribe(subscription)
    if not completed:
        return {'ok': False, 'error': (
            f'no completion event within {EXECUTE_TIMEOUT_SECONDS:.0f}s')}
    return outcome


class BridgeRequestHandler(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            try:
                request = json.loads(line)
                operation = request['op']
                if operation == 'state':
                    reply = read_state()
                elif operation == 'execute':
                    with motion_lock:
                        reply = execute_waypoints(request['waypoints_deg'])
                elif operation == 'twist':
                    reply = apply_twist(
                        request['linear'], request['angular'])
                elif operation == 'stop':
                    base.Stop()
                    reply = {'ok': True}
                else:
                    reply = {'ok': False, 'error': f'unknown op {operation}'}
            except Exception as error:
                reply = {'ok': False, 'error': str(error)}
            self.wfile.write((json.dumps(reply) + '\n').encode())


class BridgeServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


print(f'kinova link6 bridge connected to {args.robot_ip}, '
      f'serving on {BRIDGE_HOST}:{BRIDGE_PORT}')
threading.Thread(target=run_twist_watchdog, daemon=True).start()
server = BridgeServer((BRIDGE_HOST, BRIDGE_PORT), BridgeRequestHandler)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    session_client.CloseSession()
    router.SetActivationStatus(False)
    transport.disconnect()
