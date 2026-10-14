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
import threading
import time

from kortex_api.autogen.client_stubs.BaseClientRpc import BaseClient
from kortex_api.autogen.client_stubs.ProgramRunnerClientRpc import ProgramRunnerClient
from kortex_api.autogen.client_stubs.SessionClientRpc import SessionClient
from kortex_api.autogen.messages import Base_pb2, ProgramRunner_pb2, Session_pb2
from kortex_api.autogen.messages.Common_pb2 import (
    OPERATING_MODE_AUTO, OPERATING_MODE_MONITORED_STOP, ModeSelection)
from kortex_api.MqttTransport import MqttTransport
from kortex_api.RouterClient import RouterClient

RECOVERY_TIMEOUT_SECONDS = 90.0
PROGRAM_TIMEOUT_SECONDS = 120.0
MODE_SETTLE_SECONDS = 2.0
FAULT_CLEAR_SETTLE_SECONDS = 1.0
ARM_STATE_POLL_SECONDS = 0.5
SESSION_INACTIVITY_TIMEOUT_MS = 60000
CONNECTION_INACTIVITY_TIMEOUT_MS = 2000
FAULT_STATES = (Base_pb2.ARMSTATE_IN_FAULT,
                Base_pb2.ARMSTATE_IN_FAULT_POWERED_OFF)

parser = argparse.ArgumentParser()
parser.add_argument('--robot-ip', default='192.168.1.10')
parser.add_argument('--robot-username', default='admin')
parser.add_argument('--robot-password', default='admin')
parser.add_argument('--program', default='Home Position')
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
program_runner = ProgramRunnerClient(router)


def arm_state():
    return base.GetArmState().active_state


def recover_to_operational():
    state = arm_state()
    print('arm state:', Base_pb2.ArmState.Name(state))
    if state == Base_pb2.ARMSTATE_IN_UNRECOVERABLE_FAULT:
        raise SystemExit(
            'arm reports an unrecoverable fault, follow the user guide '
            'recovery procedure (p.111)')
    if state in FAULT_STATES:
        print('clearing faults')
        base.ClearFaults()
        time.sleep(FAULT_CLEAR_SETTLE_SECONDS)
    if arm_state() != Base_pb2.ARMSTATE_ARM_OPERATIONAL:
        print('activating robot')
        base.ActivateRobot()
    deadline = time.monotonic() + RECOVERY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if arm_state() == Base_pb2.ARMSTATE_ARM_OPERATIONAL:
            print('arm operational')
            return
        time.sleep(ARM_STATE_POLL_SECONDS)
    raise SystemExit(
        f'arm not operational within {RECOVERY_TIMEOUT_SECONDS:.0f}s, '
        f'state {Base_pb2.ArmState.Name(arm_state())}')


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


def run_program(program_name):
    programs = program_runner.ReadAllPrograms()
    handles_by_name = {program.name: program.handle.identifier
                       for program in programs.programs}
    if program_name not in handles_by_name:
        raise SystemExit(
            f'no program named {program_name!r} on the controller; '
            f'available: {sorted(handles_by_name)}')
    handle = handles_by_name[program_name]

    validation_configuration = (
        ProgramRunner_pb2.ProgramValidationConfiguration())
    validation_configuration.is_valid = True
    validation_configuration.program_handle.identifier = handle
    program_runner.ValidateProgram(validation_configuration)

    ensure_operating_mode(OPERATING_MODE_AUTO)

    finished = threading.Event()
    outcome = {}

    def on_execution_event(notification):
        if notification.event == ProgramRunner_pb2.EXECUTION_EVENT_COMPLETED:
            outcome['ok'] = True
            finished.set()
        elif notification.event in (ProgramRunner_pb2.EXECUTION_EVENT_FAILED,
                                    ProgramRunner_pb2.EXECUTION_EVENT_STOPPED):
            outcome['ok'] = False
            outcome['error'] = str(notification)
            finished.set()

    subscription = program_runner.OnNotificationExecutionEventTopic(
        on_execution_event, Base_pb2.NotificationOptions())
    start_configuration = ProgramRunner_pb2.ProgramStartConfiguration()
    start_configuration.handle.program_handle.identifier = handle
    print(f'running program {program_name!r}')
    program_runner.Start(start_configuration)
    completed = finished.wait(PROGRAM_TIMEOUT_SECONDS)
    program_runner.Unsubscribe(subscription)
    if not completed:
        raise SystemExit(
            f'program did not finish within {PROGRAM_TIMEOUT_SECONDS:.0f}s')
    if not outcome['ok']:
        raise SystemExit(f"program failed: {outcome.get('error')}")
    print('program completed')


try:
    recover_to_operational()
    run_program(args.program)
finally:
    session_client.CloseSession()
    router.SetActivationStatus(False)
    transport.disconnect()
