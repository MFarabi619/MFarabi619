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


import inspect
import math
from unittest.mock import create_autospec

from nav_msgs.msg import Odometry
from pymavlink.dialects.v20 import common as mavlink
import pytest
from sensor_msgs.msg import NavSatFix, NavSatStatus

GROUND_STATION = (255, mavlink.MAV_COMP_ID_MISSIONPLANNER)
VEHICLE = (1, mavlink.MAV_COMP_ID_AUTOPILOT1)
DEGE7_PER_DEGREE = 1e7
WAYPOINT = mavlink.MAV_CMD_NAV_WAYPOINT
CHANGE_SPEED = mavlink.MAV_CMD_DO_CHANGE_SPEED
RELATIVE_ALTITUDE_FRAME = mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT
MISSION = mavlink.MAV_MISSION_TYPE_MISSION
FENCE = mavlink.MAV_MISSION_TYPE_FENCE
EAST_VARIANCE_INDEX = 0
NORTH_VARIANCE_INDEX = 4
UNKNOWN_UINT16 = 65535
FLOAT32_DEGREES_RESOLUTION_DEGE7 = 100

QGROUNDCONTROL_PLAN = [
    (WAYPOINT, 45.3191, -75.7558),
    (CHANGE_SPEED, 0.0, 0.0),
    (WAYPOINT, 45.3192, -75.7557),
    (WAYPOINT, 45.3193, -75.7556),
]


def from_ground_station(encode_name, *fields):
    sender = mavlink.MAVLink(None, srcSystem=GROUND_STATION[0], srcComponent=GROUND_STATION[1])
    packet = getattr(sender, encode_name)(*fields).pack(sender)
    return mavlink.MAVLink(None).decode(bytearray(packet))


def sent_fields(call, send_name):
    return inspect.signature(getattr(mavlink.MAVLink, send_name)).bind(
        None, *call.args, **call.kwargs).arguments


def every_sent(sender, send_name):
    return [sent_fields(call, send_name) for call in getattr(sender, send_name).call_args_list]


def last_sent(sender, send_name):
    return sent_fields(getattr(sender, send_name).call_args, send_name)


def plan_item(sequence, plan_step):
    command, latitude_degrees, longitude_degrees = plan_step
    return from_ground_station(
        'mission_item_int_encode', *VEHICLE, sequence, RELATIVE_ALTITUDE_FRAME, command, 0, 1,
        0.0, 0.0, 0.0, 0.0, round(latitude_degrees * DEGE7_PER_DEGREE),
        round(longitude_degrees * DEGE7_PER_DEGREE), 0.0, MISSION)


@pytest.fixture
def mission_protocol(ground_station_bridge):
    events = []
    protocol = ground_station_bridge.MissionProtocol(
        create_autospec(mavlink.MAVLink, instance=True),
        on_mission_replaced=lambda items: events.append(('replaced', items)),
        on_mission_cleared=lambda: events.append(('cleared', None)))
    protocol.events = events
    return protocol


def upload_plan(mission_protocol, plan, now=0.0):
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, len(plan), MISSION), now)
    for sequence, plan_step in enumerate(plan):
        mission_protocol.handle(plan_item(sequence, plan_step), now)


def test_upload_requests_every_item_then_accepts(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    requested_sequences = [fields['seq'] for fields in every_sent(
        mission_protocol.sender, 'mission_request_int_send')]
    assert requested_sequences == [0, 1, 2, 3]
    assert last_sent(mission_protocol.sender, 'mission_ack_send')['type'] == (
        mavlink.MAV_MISSION_ACCEPTED)
    assert [item.seq for item in mission_protocol.mission_items] == [0, 1, 2, 3]
    assert mission_protocol.events[-1][0] == 'replaced'


def test_out_of_order_item_is_requested_again(mission_protocol):
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, 2, MISSION), 0.0)
    mission_protocol.handle(plan_item(1, (WAYPOINT, 45.0, -75.0)), 0.0)
    assert last_sent(mission_protocol.sender, 'mission_request_int_send')['seq'] == 0
    assert mission_protocol.mission_items == []


def test_unanswered_request_is_retried_then_cancelled(mission_protocol, ground_station_bridge):
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, 2, MISSION), 0.0)
    for attempt in range(ground_station_bridge.ITEM_REQUEST_MAX_ATTEMPTS):
        mission_protocol.retry_overdue_request(1.0 + attempt)
    assert mission_protocol.sender.mission_request_int_send.call_count == (
        ground_station_bridge.ITEM_REQUEST_MAX_ATTEMPTS)
    assert last_sent(mission_protocol.sender, 'mission_ack_send')['type'] == (
        mavlink.MAV_MISSION_OPERATION_CANCELLED)
    assert mission_protocol.upload is None


def test_failed_upload_keeps_the_previous_mission(mission_protocol, ground_station_bridge):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, 2, MISSION), 0.0)
    for attempt in range(ground_station_bridge.ITEM_REQUEST_MAX_ATTEMPTS):
        mission_protocol.retry_overdue_request(1.0 + attempt)
    assert mission_protocol.upload is None
    assert len(mission_protocol.mission_items) == len(QGROUNDCONTROL_PLAN)


def test_fence_upload_is_refused(mission_protocol):
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, 0, FENCE), 0.0)
    assert last_sent(mission_protocol.sender, 'mission_ack_send')['type'] == (
        mavlink.MAV_MISSION_UNSUPPORTED)
    assert mission_protocol.events == []


def test_empty_upload_clears_the_mission(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    mission_protocol.handle(
        from_ground_station('mission_count_encode', *VEHICLE, 0, MISSION), 0.0)
    assert mission_protocol.mission_items == []
    assert mission_protocol.events[-1][0] == 'cleared'


def test_download_returns_the_stored_mission(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    mission_protocol.handle(
        from_ground_station('mission_request_list_encode', *VEHICLE, MISSION), 0.0)
    assert last_sent(mission_protocol.sender, 'mission_count_send')['count'] == (
        len(QGROUNDCONTROL_PLAN))
    mission_protocol.handle(
        from_ground_station('mission_request_int_encode', *VEHICLE, 2, MISSION), 0.0)
    item = last_sent(mission_protocol.sender, 'mission_item_int_send')
    assert item['seq'] == 2
    assert (item['x'], item['y']) == (453192000, -757557000)
    assert item['current'] == 0


def test_clear_all_of_fence_keeps_the_mission(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    mission_protocol.handle(
        from_ground_station('mission_clear_all_encode', *VEHICLE, FENCE), 0.0)
    assert len(mission_protocol.mission_items) == len(QGROUNDCONTROL_PLAN)
    mission_protocol.handle(
        from_ground_station('mission_clear_all_encode', *VEHICLE, MISSION), 0.0)
    assert mission_protocol.mission_items == []


def test_reaching_an_item_advances_the_current_item(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    mission_protocol.report_item_reached(2)
    assert last_sent(mission_protocol.sender, 'mission_item_reached_send')['seq'] == 2
    assert last_sent(mission_protocol.sender, 'mission_current_send')['seq'] == 3


def test_set_current_rejects_unknown_items(mission_protocol):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    assert mission_protocol.set_current(1)
    assert not mission_protocol.set_current(len(QGROUNDCONTROL_PLAN))
    assert mission_protocol.current_sequence == 1


def test_waypoints_start_at_the_current_item(mission_protocol, ground_station_bridge):
    upload_plan(mission_protocol, QGROUNDCONTROL_PLAN)
    waypoints = ground_station_bridge.mission_waypoints(mission_protocol.mission_items, 1)
    assert [waypoint.sequence for waypoint in waypoints] == [2, 3]
    assert (waypoints[0].latitude_degrees, waypoints[0].longitude_degrees) == pytest.approx(
        (45.3192, -75.7557))
    assert ground_station_bridge.ignored_commands(mission_protocol.mission_items) == [
        CHANGE_SPEED]


def test_legacy_mission_item_degrees_become_dege7(ground_station_bridge):
    message = from_ground_station(
        'mission_item_encode', *VEHICLE, 0, RELATIVE_ALTITUDE_FRAME, WAYPOINT, 0, 1,
        0.0, 0.0, 0.0, 0.0, 45.3191, -75.7558, 0.0, MISSION)
    item = ground_station_bridge.mission_item_from_message(message)
    assert (item.x, item.y) == pytest.approx(
        (453191000, -757558000), abs=FLOAT32_DEGREES_RESOLUTION_DEGE7)


def test_set_home_position_from_command_long(ground_station_bridge):
    message = from_ground_station(
        'command_long_encode', *VEHICLE, mavlink.MAV_CMD_DO_SET_HOME, 0,
        mavlink.MAV_BOOL_FALSE, 0.0, 0.0, math.nan, 45.3191, -75.7558, 62.5)
    position = ground_station_bridge.commanded_position(message)
    assert position == pytest.approx((45.3191, -75.7558, 62.5))


def test_set_home_position_from_command_int(ground_station_bridge):
    message = from_ground_station(
        'command_int_encode', *VEHICLE, mavlink.MAV_FRAME_GLOBAL, mavlink.MAV_CMD_DO_SET_HOME,
        0, 0, mavlink.MAV_BOOL_FALSE, 0.0, 0.0, math.nan, 453191000, -757558000, 62.5)
    position = ground_station_bridge.commanded_position(message)
    assert position == pytest.approx((45.3191, -75.7558, 62.5))


def navsat_fix(status, horizontal_variance_square_meters=0.0,
               covariance_type=NavSatFix.COVARIANCE_TYPE_APPROXIMATED):
    message = NavSatFix()
    message.status.status = status
    message.position_covariance[EAST_VARIANCE_INDEX] = horizontal_variance_square_meters
    message.position_covariance[NORTH_VARIANCE_INDEX] = horizontal_variance_square_meters
    message.position_covariance_type = covariance_type
    return message


@pytest.mark.parametrize(('fix', 'expected'), [
    (navsat_fix(NavSatStatus.STATUS_NO_FIX), mavlink.GPS_FIX_TYPE_NO_FIX),
    (navsat_fix(NavSatStatus.STATUS_FIX), mavlink.GPS_FIX_TYPE_3D_FIX),
    (navsat_fix(NavSatStatus.STATUS_SBAS_FIX), mavlink.GPS_FIX_TYPE_DGPS),
    (navsat_fix(NavSatStatus.STATUS_GBAS_FIX, horizontal_variance_square_meters=0.02 ** 2),
     mavlink.GPS_FIX_TYPE_RTK_FIXED),
    (navsat_fix(NavSatStatus.STATUS_GBAS_FIX, horizontal_variance_square_meters=4.0 ** 2),
     mavlink.GPS_FIX_TYPE_RTK_FLOAT),
    (navsat_fix(NavSatStatus.STATUS_GBAS_FIX, covariance_type=NavSatFix.COVARIANCE_TYPE_UNKNOWN),
     mavlink.GPS_FIX_TYPE_RTK_FLOAT),
])
def test_gps_fix_type(ground_station_bridge, fix, expected):
    assert ground_station_bridge.gps_fix_type(fix) == expected


def odometry_facing(yaw_radians):
    message = Odometry()
    message.pose.pose.orientation.z = math.sin(yaw_radians / 2.0)
    message.pose.pose.orientation.w = math.cos(yaw_radians / 2.0)
    return message


@pytest.mark.parametrize(('yaw_radians', 'expected_heading_degrees'), [
    (0.0, 90.0),
    (math.pi / 2.0, 0.0),
    (math.pi, 270.0),
    (-math.pi / 2.0, 180.0),
])
def test_compass_heading_from_east_north_up_yaw(
        ground_station_bridge, yaw_radians, expected_heading_degrees):
    heading_degrees = ground_station_bridge.compass_heading_degrees(odometry_facing(yaw_radians))
    assert heading_degrees == pytest.approx(expected_heading_degrees)


@pytest.mark.parametrize(('heading_degrees', 'expected_centidegrees'), [
    (None, UNKNOWN_UINT16),
    (0.0, 0),
    (123.456, 12346),
    (359.999, 0),
])
def test_heading_centidegrees(ground_station_bridge, heading_degrees, expected_centidegrees):
    assert ground_station_bridge.heading_centidegrees(heading_degrees) == expected_centidegrees


@pytest.mark.parametrize(('heading_degrees', 'expected_yaw_degrees'), [
    (0.0, 0.0),
    (90.0, 90.0),
    (270.0, -90.0),
])
def test_north_east_down_yaw(ground_station_bridge, heading_degrees, expected_yaw_degrees):
    yaw_radians = ground_station_bridge.north_east_down_yaw_radians(heading_degrees)
    assert math.degrees(yaw_radians) == pytest.approx(expected_yaw_degrees)
