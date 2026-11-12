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


import threading
import time

import pytest

from kortex_api.autogen.client_stubs.BaseClientRpc import BaseClient
from kortex_api.autogen.client_stubs.BaseCyclicClientRpc import BaseCyclicClient
from kortex_api.autogen.client_stubs.ProgramRunnerClientRpc import ProgramRunnerClient
from kortex_api.autogen.client_stubs.SessionClientRpc import SessionClient
from kortex_api.autogen.messages import Base_pb2, Session_pb2
from kortex_api.autogen.messages.Common_pb2 import (
    OPERATING_MODE_AUTO, OPERATING_MODE_MONITORED_STOP, ModeSelection)
from kortex_api.exceptions.KServerException import KServerException
from kortex_api.MqttTransport import MqttTransport
from kortex_api.RouterClient import RouterClient

JOINT_COUNT = 6
POSE_TOLERANCE_DEGREES = 1.0
OUT_OF_RANGE_OFFSET_DEGREES = 1000.0
EXECUTE_TIMEOUT_SECONDS = 120.0
RECOVERY_TIMEOUT_SECONDS = 90.0
MODE_SETTLE_SECONDS = 2.0
MOTION_SETTLE_SECONDS = 0.3
FAULT_CLEAR_SETTLE_SECONDS = 1.0
ARM_STATE_POLL_SECONDS = 0.5
SESSION_INACTIVITY_TIMEOUT_MILLISECONDS = 60000
CONNECTION_INACTIVITY_TIMEOUT_MILLISECONDS = 2000
STOP_AT_WAYPOINT_BLENDING = 0.0
TRAVEL_MAX_VELOCITY_DEGREES_PER_SECOND = 20.0
SWEEP_BASE_POSE_DEGREES = [0.0, 10.0, 25.0, 0.0, 0.0, 0.0]
HOME_POSE_DEGREES = [0.0, -20.0, 110.0, 0.0, 40.0, 0.0]
SWEEP_RANGES_DEGREES = {
    1: (-170.0, 170.0),
    2: (-30.0, 30.0),
    3: (-30.0, 30.0),
    4: (-60.0, 60.0),
    5: (-60.0, 60.0),
    6: (-90.0, 90.0),
}
SWEEP_MAX_VELOCITIES_DEGREES_PER_SECOND = {
    1: 60.0, 2: 20.0, 3: 20.0, 4: 60.0, 5: 60.0, 6: 80.0}


@pytest.fixture(scope='session')
def kortex_router(request):
    transport = MqttTransport()
    transport.connect(request.config.getoption('--robot-ip'))
    kortex_router = RouterClient(transport, errorCallback=None)
    session = Session_pb2.CreateSessionInfo()
    session.username = request.config.getoption('--robot-username')
    session.password = request.config.getoption('--robot-password')
    session.session_inactivity_timeout = SESSION_INACTIVITY_TIMEOUT_MILLISECONDS
    session.connection_inactivity_timeout = (
        CONNECTION_INACTIVITY_TIMEOUT_MILLISECONDS)
    session_client = SessionClient(kortex_router)
    session_client.CreateSession(session)
    yield kortex_router
    session_client.CloseSession()
    kortex_router.SetActivationStatus(False)
    transport.disconnect()


@pytest.fixture(scope='session')
def base(kortex_router):
    return BaseClient(kortex_router)


@pytest.fixture(scope='session')
def base_cyclic(kortex_router):
    return BaseCyclicClient(kortex_router)


@pytest.fixture(scope='session')
def program_runner(kortex_router):
    return ProgramRunnerClient(kortex_router)


@pytest.fixture(scope='session', autouse=True)
def operational_arm(base):
    """Base.ClearFaults then Base.ActivateRobot, polled until operational;
    stale waypoint actions from an aborted run are stopped as well."""
    state = base.GetArmState().active_state
    if state in (Base_pb2.ARMSTATE_IN_FAULT,
                 Base_pb2.ARMSTATE_IN_FAULT_POWERED_OFF):
        base.ClearFaults()
        time.sleep(FAULT_CLEAR_SETTLE_SECONDS)
    if base.GetArmState().active_state != Base_pb2.ARMSTATE_ARM_OPERATIONAL:
        base.ActivateRobot()
    deadline = time.monotonic() + RECOVERY_TIMEOUT_SECONDS
    while (base.GetArmState().active_state
           != Base_pb2.ARMSTATE_ARM_OPERATIONAL
           and time.monotonic() < deadline):
        time.sleep(ARM_STATE_POLL_SECONDS)
    final_state = base.GetArmState().active_state
    assert final_state == Base_pb2.ARMSTATE_ARM_OPERATIONAL, \
        f'arm stuck in {Base_pb2.ArmState.Name(final_state)}'
    for flush_stale_action in (base.StopAction, base.Stop):
        try:
            flush_stale_action()
        except KServerException:
            pass


def current_positions_degrees(base_cyclic):
    return [actuator.position for actuator
            in base_cyclic.RefreshFeedback().actuators]


def ensure_operating_mode(base, operating_mode):
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


def execute_waypoints(base, waypoints_degrees,
                      max_velocity_degrees_per_second=
                      TRAVEL_MAX_VELOCITY_DEGREES_PER_SECOND):
    waypoint_list = Base_pb2.WaypointList()
    for index, angles in enumerate(waypoints_degrees):
        waypoint = waypoint_list.waypoints.add()
        waypoint.name = f'waypoint_{index}'
        waypoint.angular_waypoint.angles.extend(angles)
        waypoint.angular_waypoint.maximum_velocities.extend(
            [max_velocity_degrees_per_second] * JOINT_COUNT)
        waypoint.angular_waypoint.blending = STOP_AT_WAYPOINT_BLENDING
    validation = base.ValidateWaypointList(waypoint_list)
    assert not validation.trajectory_error_report.trajectory_error_elements, \
        str(validation.trajectory_error_report)

    ensure_operating_mode(base, OPERATING_MODE_AUTO)

    finished = threading.Event()
    outcome = {}

    def on_action_event(notification):
        if notification.action_event == Base_pb2.ACTION_END:
            outcome['succeeded'] = True
            finished.set()
        elif notification.action_event == Base_pb2.ACTION_ABORT:
            outcome['succeeded'] = False
            outcome['error'] = str(notification)
            finished.set()

    subscription = base.OnNotificationActionTopic(
        on_action_event, Base_pb2.NotificationOptions())
    base.ExecuteWaypointTrajectory(waypoint_list)
    completed = finished.wait(EXECUTE_TIMEOUT_SECONDS)
    base.Unsubscribe(subscription)
    assert completed, \
        f'no completion event within {EXECUTE_TIMEOUT_SECONDS:.0f}s'
    assert outcome['succeeded'], \
        f"trajectory aborted: {outcome.get('error')}"
    time.sleep(MOTION_SETTLE_SECONDS)


def assert_at_pose(base_cyclic, pose_degrees):
    assert current_positions_degrees(base_cyclic) == pytest.approx(
        pose_degrees, abs=POSE_TOLERANCE_DEGREES)


def test_robot_identifies_itself(base):
    """A session over MQTT port 1883 reaches a live arm; Web App and pendant
    logins outrank API sessions, so the Web App must be signed out."""
    state = base.GetArmState()
    print('arm state:', Base_pb2.ArmState.Name(state.active_state))
    versions = base.GetFirmwareBundleVersions()
    print('firmware bundle:', versions)
    assert state.active_state in Base_pb2.ArmState.values()


def test_feedback_reports_six_joints(base_cyclic):
    """BaseCyclic.RefreshFeedback snapshots every actuator in degrees, deg/s
    and Nm, plus the commanded and measured tool pose."""
    feedback = base_cyclic.RefreshFeedback()
    assert len(feedback.actuators) == JOINT_COUNT
    for index, actuator in enumerate(feedback.actuators):
        print(f'joint_{index + 1}  position {actuator.position:9.3f} deg  '
              f'velocity {actuator.velocity:8.3f} deg/s  '
              f'torque {actuator.torque:8.3f} Nm')
    base_feedback = feedback.base
    print(f'tool pose  x {base_feedback.tool_pose_x:.4f}  '
          f'y {base_feedback.tool_pose_y:.4f}  '
          f'z {base_feedback.tool_pose_z:.4f} m')


def test_webapp_programs_are_listable(program_runner):
    """ProgramRunner.ReadAllPrograms lists pendant-taught Web App programs,
    which the API can validate and start remotely."""
    programs = program_runner.ReadAllPrograms()
    for program in programs.programs:
        print(f'program {program.handle.identifier}: {program.name}')
    print(f'{len(programs.programs)} programs stored on the controller')


def test_validation_is_a_dry_run(base, base_cyclic):
    """ValidateWaypointList checks a trajectory on the controller without
    motion: an absurd target is rejected, a sane one is accepted."""
    current_pose_degrees = current_positions_degrees(base_cyclic)
    out_of_range_waypoint_list = Base_pb2.WaypointList()
    waypoint = out_of_range_waypoint_list.waypoints.add()
    waypoint.name = 'out_of_range'
    waypoint.angular_waypoint.angles.extend(
        [angle + OUT_OF_RANGE_OFFSET_DEGREES for angle in current_pose_degrees])
    report = base.ValidateWaypointList(
        out_of_range_waypoint_list).trajectory_error_report
    assert report.trajectory_error_elements, \
        f'a +{OUT_OF_RANGE_OFFSET_DEGREES:.0f} deg waypoint should fail validation'
    print('out-of-range waypoint rejected with',
          len(report.trajectory_error_elements), 'error elements')

    hold_position_waypoint_list = Base_pb2.WaypointList()
    waypoint = hold_position_waypoint_list.waypoints.add()
    waypoint.name = 'hold_position'
    waypoint.angular_waypoint.angles.extend(current_pose_degrees)
    report = base.ValidateWaypointList(
        hold_position_waypoint_list).trajectory_error_report
    assert not report.trajectory_error_elements
    print('hold-position waypoint accepted')


def test_moves_to_sweep_base_pose(base, base_cyclic):
    """First motion: ExecuteWaypointTrajectory in AUTO mode to the sweep
    base pose, which stays clear of the singular straight-arm alignments."""
    execute_waypoints(base, [SWEEP_BASE_POSE_DEGREES])
    assert_at_pose(base_cyclic, SWEEP_BASE_POSE_DEGREES)


@pytest.mark.parametrize('joint_number', [1, 2, 3, 4, 5, 6],
                         ids=lambda joint_number: f'joint_{joint_number}')
def test_sweeps_joint_through_range(base, base_cyclic, joint_number):
    """Sweeps one joint min, max, base inside SWEEP_RANGES_DEGREES, this file's
    safety envelope for a table mount; the controller validates each sweep
    against the robot's configured limits before any motion."""
    low, high = SWEEP_RANGES_DEGREES[joint_number]
    max_velocity_degrees_per_second = (
        SWEEP_MAX_VELOCITIES_DEGREES_PER_SECOND[joint_number])
    print(f'sweeping joint_{joint_number} through {low:.0f} to {high:.0f} deg '
          f'at {max_velocity_degrees_per_second:.0f} deg/s')
    base_value = SWEEP_BASE_POSE_DEGREES[joint_number - 1]
    sweep_waypoints_degrees = []
    for target in (low, high, base_value):
        pose_degrees = list(SWEEP_BASE_POSE_DEGREES)
        pose_degrees[joint_number - 1] = target
        sweep_waypoints_degrees.append(pose_degrees)
    execute_waypoints(base, sweep_waypoints_degrees, max_velocity_degrees_per_second)
    assert_at_pose(base_cyclic, SWEEP_BASE_POSE_DEGREES)


def test_returns_to_home_pose(base, base_cyclic):
    """The suite ends by leaving the arm at the factory home pose."""
    execute_waypoints(base, [HOME_POSE_DEGREES])
    assert_at_pose(base_cyclic, HOME_POSE_DEGREES)
