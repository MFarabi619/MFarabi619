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


from collections import namedtuple
from dataclasses import dataclass, field
import math
import os
import time

from action_msgs.msg import GoalStatus
from geographic_msgs.msg import GeoPoint, GeoPose
from nav2_msgs.action import FollowGPSWaypoints
from nav_msgs.msg import Odometry
from pymavlink import mavutil
from pymavlink.dialects.v20 import common as mavlink
import rclpy
from rclpy.action import ActionClient
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import NavSatFix, NavSatStatus
from std_srvs.srv import Trigger

DEGE7_PER_DEGREE = 1e7
MILLIMETERS_PER_METER = 1000.0
MILLISECONDS_PER_SECOND = 1000.0
NANOSECONDS_PER_MICROSECOND = 1000
CENTIDEGREES_PER_DEGREE = 100.0
CENTIDEGREES_PER_TURN = 36000
DEGREES_PER_TURN = 360.0
COMPASS_NORTH_FROM_EAST_DEGREES = 90.0
UNKNOWN_UINT16 = 65535
UNKNOWN_SATELLITE_COUNT = 255
EAST_VARIANCE_INDEX = 0
NORTH_VARIANCE_INDEX = 4
UP_VARIANCE_INDEX = 8
RTK_FIXED_MAX_HORIZONTAL_STANDARD_DEVIATION_METERS = 0.1
ITEM_REQUEST_TIMEOUT_SECONDS = 0.25
ITEM_REQUEST_MAX_ATTEMPTS = 6
RECEIVE_POLL_PERIOD_SECONDS = 0.02
STATUS_PERIOD_SECONDS = 1.0
DEFAULT_GROUND_STATION_URL = 'udpout:127.0.0.1:14550'
BROADCAST_SYSTEM_ID = 0
IDENTITY_QUATERNION = (1.0, 0.0, 0.0, 0.0)
UNSET_CUSTOM_VERSION = (0,) * 8
VEHICLE_CAPABILITIES = (
    mavlink.MAV_PROTOCOL_CAPABILITY_MISSION_INT
    | mavlink.MAV_PROTOCOL_CAPABILITY_COMMAND_INT
    | mavlink.MAV_PROTOCOL_CAPABILITY_MAVLINK2
)

MissionItem = namedtuple('MissionItem', (
    'seq', 'frame', 'command', 'current', 'autocontinue',
    'param1', 'param2', 'param3', 'param4', 'x', 'y', 'z'))
Waypoint = namedtuple('Waypoint', ('sequence', 'latitude_degrees', 'longitude_degrees'))
Position = namedtuple('Position', ('latitude_degrees', 'longitude_degrees', 'altitude_meters'))
CommandOutcome = namedtuple('CommandOutcome', ('result', 'text'))


@dataclass
class MissionUpload:
    source: tuple
    count: int
    items: list = field(default_factory=list)
    attempts: int = 0
    deadline: float = 0.0


def mission_item_from_message(message):
    item = MissionItem._make(getattr(message, name) for name in MissionItem._fields)
    if message.get_type() == 'MISSION_ITEM':
        return item._replace(
            x=round(message.x * DEGE7_PER_DEGREE), y=round(message.y * DEGE7_PER_DEGREE))
    return item


def mission_waypoints(mission_items, first_sequence=0):
    return [
        Waypoint(item.seq, item.x / DEGE7_PER_DEGREE, item.y / DEGE7_PER_DEGREE)
        for item in mission_items
        if item.command == mavlink.MAV_CMD_NAV_WAYPOINT and item.seq >= first_sequence
    ]


def ignored_commands(mission_items):
    return sorted({
        item.command for item in mission_items if item.command != mavlink.MAV_CMD_NAV_WAYPOINT
    })


def clears_mission(mission_type):
    return mission_type in (mavlink.MAV_MISSION_TYPE_MISSION, mavlink.MAV_MISSION_TYPE_ALL)


def horizontal_standard_deviation_meters(fix):
    covariance = fix.position_covariance
    return math.sqrt(max(covariance[EAST_VARIANCE_INDEX], covariance[NORTH_VARIANCE_INDEX]))


def vertical_standard_deviation_meters(fix):
    return math.sqrt(fix.position_covariance[UP_VARIANCE_INDEX])


def gps_fix_type(fix):
    status = fix.status.status
    if status == NavSatStatus.STATUS_FIX:
        return mavlink.GPS_FIX_TYPE_3D_FIX
    if status == NavSatStatus.STATUS_SBAS_FIX:
        return mavlink.GPS_FIX_TYPE_DGPS
    if status == NavSatStatus.STATUS_GBAS_FIX:
        if fix.position_covariance_type == NavSatFix.COVARIANCE_TYPE_UNKNOWN:
            return mavlink.GPS_FIX_TYPE_RTK_FLOAT
        if (horizontal_standard_deviation_meters(fix)
                <= RTK_FIXED_MAX_HORIZONTAL_STANDARD_DEVIATION_METERS):
            return mavlink.GPS_FIX_TYPE_RTK_FIXED
        return mavlink.GPS_FIX_TYPE_RTK_FLOAT
    return mavlink.GPS_FIX_TYPE_NO_FIX


def compass_heading_degrees(odometry):
    orientation = odometry.pose.pose.orientation
    yaw_radians = math.atan2(
        2.0 * (orientation.w * orientation.z + orientation.x * orientation.y),
        1.0 - 2.0 * (orientation.y * orientation.y + orientation.z * orientation.z))
    return (COMPASS_NORTH_FROM_EAST_DEGREES - math.degrees(yaw_radians)) % DEGREES_PER_TURN


def heading_centidegrees(heading_degrees):
    if heading_degrees is None:
        return UNKNOWN_UINT16
    return round(heading_degrees * CENTIDEGREES_PER_DEGREE) % CENTIDEGREES_PER_TURN


def north_east_down_yaw_radians(heading_degrees):
    return math.radians(math.remainder(heading_degrees, DEGREES_PER_TURN))


def commanded_position(message):
    if message.get_type() == 'COMMAND_INT':
        return Position(
            message.x / DEGE7_PER_DEGREE, message.y / DEGE7_PER_DEGREE, message.z)
    return Position(message.param5, message.param6, message.param7)


def fix_position(fix):
    return Position(fix.latitude, fix.longitude, fix.altitude)


def geo_pose(waypoint):
    return GeoPose(position=GeoPoint(
        latitude=waypoint.latitude_degrees, longitude=waypoint.longitude_degrees))


class MissionProtocol:
    def __init__(self, sender, on_mission_replaced, on_mission_cleared):
        self.sender = sender
        self.on_mission_replaced = on_mission_replaced
        self.on_mission_cleared = on_mission_cleared
        self.mission_items = []
        self.current_sequence = 0
        self.upload = None

    def handle(self, message, now):
        handlers = {
            'MISSION_COUNT': self.on_count,
            'MISSION_ITEM_INT': self.on_item,
            'MISSION_ITEM': self.on_item,
            'MISSION_REQUEST_LIST': self.on_request_list,
            'MISSION_REQUEST_INT': self.on_request,
            'MISSION_REQUEST': self.on_request,
            'MISSION_CLEAR_ALL': self.on_clear_all,
            'MISSION_SET_CURRENT': self.on_set_current,
        }
        handler = handlers.get(message.get_type())
        if handler is not None:
            handler(message, now)

    def on_count(self, message, now):
        source = (message.get_srcSystem(), message.get_srcComponent())
        if message.mission_type != mavlink.MAV_MISSION_TYPE_MISSION:
            self.sender.mission_ack_send(
                *source, mavlink.MAV_MISSION_UNSUPPORTED, message.mission_type)
            return
        if message.count == 0:
            self.clear()
            self.sender.mission_ack_send(
                *source, mavlink.MAV_MISSION_ACCEPTED, mavlink.MAV_MISSION_TYPE_MISSION)
            return
        self.upload = MissionUpload(source, message.count)
        self.request_next_item(now)

    def on_item(self, message, now):
        if self.upload is None or message.mission_type != mavlink.MAV_MISSION_TYPE_MISSION:
            return
        if message.seq != len(self.upload.items):
            self.request_next_item(now)
            return
        self.upload.items.append(mission_item_from_message(message))
        self.upload.attempts = 0
        if len(self.upload.items) < self.upload.count:
            self.request_next_item(now)
            return
        upload = self.upload
        self.upload = None
        self.mission_items = upload.items
        self.sender.mission_ack_send(
            *upload.source, mavlink.MAV_MISSION_ACCEPTED, mavlink.MAV_MISSION_TYPE_MISSION)
        self.set_current(0)
        self.on_mission_replaced(upload.items)

    def request_next_item(self, now):
        self.upload.attempts += 1
        self.upload.deadline = now + ITEM_REQUEST_TIMEOUT_SECONDS
        self.sender.mission_request_int_send(
            *self.upload.source, len(self.upload.items), mavlink.MAV_MISSION_TYPE_MISSION)

    def retry_overdue_request(self, now):
        if self.upload is None or now < self.upload.deadline:
            return
        if self.upload.attempts >= ITEM_REQUEST_MAX_ATTEMPTS:
            self.sender.mission_ack_send(
                *self.upload.source, mavlink.MAV_MISSION_OPERATION_CANCELLED,
                mavlink.MAV_MISSION_TYPE_MISSION)
            self.upload = None
            return
        self.request_next_item(now)

    def on_request_list(self, message, _):
        count = len(self.mission_items)
        if message.mission_type != mavlink.MAV_MISSION_TYPE_MISSION:
            count = 0
        self.sender.mission_count_send(
            message.get_srcSystem(), message.get_srcComponent(), count, message.mission_type)

    def on_request(self, message, _):
        source = (message.get_srcSystem(), message.get_srcComponent())
        if (message.mission_type != mavlink.MAV_MISSION_TYPE_MISSION
                or message.seq >= len(self.mission_items)):
            self.sender.mission_ack_send(
                *source, mavlink.MAV_MISSION_INVALID_SEQUENCE, message.mission_type)
            return
        item = self.mission_items[message.seq]
        self.sender.mission_item_int_send(
            *source, *item._replace(current=int(item.seq == self.current_sequence)),
            mavlink.MAV_MISSION_TYPE_MISSION)

    def on_clear_all(self, message, _):
        if clears_mission(message.mission_type):
            self.clear()
        self.sender.mission_ack_send(
            message.get_srcSystem(), message.get_srcComponent(),
            mavlink.MAV_MISSION_ACCEPTED, message.mission_type)

    def on_set_current(self, message, _):
        self.set_current(message.seq)

    def clear(self):
        self.mission_items = []
        self.current_sequence = 0
        self.on_mission_cleared()

    def set_current(self, sequence):
        if sequence >= max(len(self.mission_items), 1):
            self.sender.statustext_send(
                mavlink.MAV_SEVERITY_WARNING, f'no mission item {sequence}'.encode())
            return False
        self.current_sequence = sequence
        self.publish_mission_current()
        return True

    def report_item_reached(self, sequence):
        self.sender.mission_item_reached_send(sequence)
        self.current_sequence = sequence + 1
        self.publish_mission_current()

    def publish_mission_current(self):
        self.sender.mission_current_send(self.current_sequence, len(self.mission_items))


class GroundStationBridge(Node):
    def __init__(self):
        super().__init__('ground_station_bridge')
        ground_station_url = self.declare_parameter(
            'ground_station_url', DEFAULT_GROUND_STATION_URL).value
        self.system_id = self.declare_parameter('system_id', 1).value
        gps_topic = self.declare_parameter('gps_topic', 'sensors/gps_0/fix').value
        odometry_topic = self.declare_parameter('odometry_topic', 'odometry/global').value

        self.boot_monotonic_seconds = time.monotonic()
        self.position = None
        self.home = None
        self.heading_degrees = None
        self.follow_goal_handle = None
        self.followed_waypoint_sequences = []
        self.reached_waypoint_count = 0

        os.environ['MAVLINK20'] = '1'
        self.connection = mavutil.mavlink_connection(
            ground_station_url, source_system=self.system_id,
            source_component=mavlink.MAV_COMP_ID_AUTOPILOT1, dialect='common')
        self.sender = self.connection.mav
        self.mission_protocol = MissionProtocol(
            self.sender,
            on_mission_replaced=self.on_mission_replaced,
            on_mission_cleared=lambda: self.stop_following('the mission was cleared'))

        self.follow_client = ActionClient(self, FollowGPSWaypoints, 'follow_gps_waypoints')
        self.create_service(Trigger, '~/start_mission', self.on_start_mission)
        self.create_service(Trigger, '~/stop_mission', self.on_stop_mission)
        self.create_subscription(NavSatFix, gps_topic, self.on_fix, qos_profile_sensor_data)
        self.create_subscription(Odometry, odometry_topic, self.on_odometry, 10)
        self.create_timer(RECEIVE_POLL_PERIOD_SECONDS, self.receive_messages)
        self.create_timer(STATUS_PERIOD_SECONDS, self.publish_status)
        self.get_logger().info(
            f'ground station bridge: system {self.system_id} on {ground_station_url}')

    def milliseconds_since_boot(self):
        return int((time.monotonic() - self.boot_monotonic_seconds) * MILLISECONDS_PER_SECOND)

    def publish_status(self):
        base_mode = mavlink.MAV_MODE_FLAG_SAFETY_ARMED if self.follow_goal_handle else 0
        self.sender.heartbeat_send(
            mavlink.MAV_TYPE_GROUND_ROVER, mavlink.MAV_AUTOPILOT_GENERIC,
            base_mode, 0, mavlink.MAV_STATE_ACTIVE)
        self.mission_protocol.publish_mission_current()
        self.publish_home()

    def publish_home(self):
        if self.home is None:
            return
        self.sender.home_position_send(
            latitude=round(self.home.latitude_degrees * DEGE7_PER_DEGREE),
            longitude=round(self.home.longitude_degrees * DEGE7_PER_DEGREE),
            altitude=round(self.home.altitude_meters * MILLIMETERS_PER_METER),
            x=0.0, y=0.0, z=0.0, q=IDENTITY_QUATERNION,
            approach_x=0.0, approach_y=0.0, approach_z=0.0)

    def on_odometry(self, odometry):
        self.heading_degrees = compass_heading_degrees(odometry)

    def on_fix(self, fix):
        fix_type = gps_fix_type(fix)
        latitude_dege7 = round(fix.latitude * DEGE7_PER_DEGREE)
        longitude_dege7 = round(fix.longitude * DEGE7_PER_DEGREE)
        altitude_millimeters = round(fix.altitude * MILLIMETERS_PER_METER)
        self.sender.gps_raw_int_send(
            time.time_ns() // NANOSECONDS_PER_MICROSECOND, fix_type,
            latitude_dege7, longitude_dege7, altitude_millimeters,
            eph=UNKNOWN_UINT16, epv=UNKNOWN_UINT16, vel=UNKNOWN_UINT16, cog=UNKNOWN_UINT16,
            satellites_visible=UNKNOWN_SATELLITE_COUNT,
            h_acc=round(horizontal_standard_deviation_meters(fix) * MILLIMETERS_PER_METER),
            v_acc=round(vertical_standard_deviation_meters(fix) * MILLIMETERS_PER_METER))
        if fix_type == mavlink.GPS_FIX_TYPE_NO_FIX:
            return
        self.position = fix_position(fix)
        if self.home is None:
            self.home = self.position
        self.sender.global_position_int_send(
            self.milliseconds_since_boot(), latitude_dege7, longitude_dege7,
            altitude_millimeters, relative_alt=0, vx=0, vy=0, vz=0,
            hdg=heading_centidegrees(self.heading_degrees))
        if self.heading_degrees is not None:
            self.sender.attitude_send(
                self.milliseconds_since_boot(), roll=0.0, pitch=0.0,
                yaw=north_east_down_yaw_radians(self.heading_degrees),
                rollspeed=0.0, pitchspeed=0.0, yawspeed=0.0)

    def receive_messages(self):
        now = time.monotonic()
        while (message := self.connection.recv_msg()) is not None:
            target_system = getattr(message, 'target_system', self.system_id)
            if target_system not in (BROADCAST_SYSTEM_ID, self.system_id):
                continue
            if message.get_type() in ('COMMAND_LONG', 'COMMAND_INT'):
                self.on_command(message)
            else:
                self.mission_protocol.handle(message, now)
        self.mission_protocol.retry_overdue_request(now)

    def on_command(self, message):
        if message.command == mavlink.MAV_CMD_MISSION_START:
            result = self.start_mission().result
        elif message.command == mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH:
            result = self.return_home().result
        elif message.command == mavlink.MAV_CMD_DO_SET_HOME:
            result = self.set_home(message)
        elif (message.command == mavlink.MAV_CMD_DO_PAUSE_CONTINUE
                and message.param1 == mavlink.MAV_BOOL_FALSE):
            self.stop_following('pause requested')
            result = mavlink.MAV_RESULT_ACCEPTED
        elif message.command == mavlink.MAV_CMD_DO_SET_MISSION_CURRENT:
            result = self.set_mission_current(int(message.param1))
        elif self.requests_autopilot_version(message):
            self.ack(message, mavlink.MAV_RESULT_ACCEPTED)
            self.sender.autopilot_version_send(
                VEHICLE_CAPABILITIES, flight_sw_version=0, middleware_sw_version=0,
                os_sw_version=0, board_version=0,
                flight_custom_version=UNSET_CUSTOM_VERSION,
                middleware_custom_version=UNSET_CUSTOM_VERSION,
                os_custom_version=UNSET_CUSTOM_VERSION, vendor_id=0, product_id=0, uid=0)
            return
        else:
            result = mavlink.MAV_RESULT_UNSUPPORTED
        self.ack(message, result)

    def requests_autopilot_version(self, message):
        if message.command == mavlink.MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES:
            return True
        return (message.command == mavlink.MAV_CMD_REQUEST_MESSAGE
                and int(message.param1) == mavlink.MAVLINK_MSG_ID_AUTOPILOT_VERSION)

    def ack(self, message, result):
        self.sender.command_ack_send(
            message.command, result, target_system=message.get_srcSystem(),
            target_component=message.get_srcComponent())

    def set_home(self, message):
        if message.param1 == mavlink.MAV_BOOL_TRUE:
            home = self.position
        else:
            home = commanded_position(message)
        if home is None or not (math.isfinite(home.latitude_degrees)
                                and math.isfinite(home.longitude_degrees)):
            return mavlink.MAV_RESULT_DENIED
        self.home = home
        self.get_logger().info(
            f'home set to {home.latitude_degrees:.7f}, {home.longitude_degrees:.7f}')
        self.publish_home()
        return mavlink.MAV_RESULT_ACCEPTED

    def set_mission_current(self, sequence):
        if self.follow_goal_handle is not None:
            return mavlink.MAV_RESULT_TEMPORARILY_REJECTED
        if not self.mission_protocol.set_current(sequence):
            return mavlink.MAV_RESULT_DENIED
        return mavlink.MAV_RESULT_ACCEPTED

    def on_mission_replaced(self, mission_items):
        self.stop_following('a new mission was uploaded')
        waypoints = mission_waypoints(mission_items)
        self.get_logger().info(
            f'mission uploaded: {len(waypoints)} waypoints in {len(mission_items)} items')
        ignored = ignored_commands(mission_items)
        if ignored:
            self.get_logger().warning(f'mission commands ignored: {ignored}')

    def on_start_mission(self, _, response):
        outcome = self.start_mission()
        response.success = outcome.result == mavlink.MAV_RESULT_ACCEPTED
        response.message = outcome.text
        return response

    def on_stop_mission(self, _, response):
        response.success = self.follow_goal_handle is not None
        response.message = 'stopping' if response.success else 'nothing is driving'
        self.stop_following('stop requested')
        return response

    def remaining_waypoints(self):
        return mission_waypoints(
            self.mission_protocol.mission_items, self.mission_protocol.current_sequence)

    def start_mission(self):
        if not mission_waypoints(self.mission_protocol.mission_items):
            return CommandOutcome(mavlink.MAV_RESULT_DENIED, 'no uploaded mission with waypoints')
        if self.follow_goal_handle is None and not self.remaining_waypoints():
            self.mission_protocol.set_current(0)
        return self.follow_waypoints(self.remaining_waypoints())

    def return_home(self):
        if self.home is None:
            return CommandOutcome(mavlink.MAV_RESULT_DENIED, 'home is not set')
        return self.follow_waypoints([
            Waypoint(None, self.home.latitude_degrees, self.home.longitude_degrees)])

    def follow_waypoints(self, waypoints):
        if self.follow_goal_handle is not None:
            return CommandOutcome(mavlink.MAV_RESULT_TEMPORARILY_REJECTED, 'already driving')
        if not self.follow_client.server_is_ready():
            return CommandOutcome(
                mavlink.MAV_RESULT_TEMPORARILY_REJECTED, 'navigation is not ready')
        self.followed_waypoint_sequences = [waypoint.sequence for waypoint in waypoints]
        self.reached_waypoint_count = 0
        goal = FollowGPSWaypoints.Goal()
        goal.gps_poses = [geo_pose(waypoint) for waypoint in waypoints]
        future = self.follow_client.send_goal_async(
            goal, feedback_callback=self.on_follow_feedback)
        future.add_done_callback(self.on_follow_goal_response)
        return CommandOutcome(mavlink.MAV_RESULT_ACCEPTED, f'driving {len(waypoints)} waypoints')

    def stop_following(self, reason):
        if self.follow_goal_handle is None:
            return
        self.get_logger().info(f'stopping: {reason}')
        self.follow_goal_handle.cancel_goal_async()
        self.follow_goal_handle = None

    def on_follow_goal_response(self, future):
        goal_handle = future.result()
        if not goal_handle.accepted:
            self.get_logger().warning('follow_gps_waypoints rejected the goal')
            return
        self.follow_goal_handle = goal_handle
        goal_handle.get_result_async().add_done_callback(
            lambda result_future: self.on_follow_result(goal_handle, result_future))

    def on_follow_feedback(self, feedback_message):
        self.report_reached_waypoints(feedback_message.feedback.current_waypoint)

    def report_reached_waypoints(self, reached_count):
        while self.reached_waypoint_count < reached_count:
            sequence = self.followed_waypoint_sequences[self.reached_waypoint_count]
            if sequence is not None:
                self.mission_protocol.report_item_reached(sequence)
            self.reached_waypoint_count += 1

    def on_follow_result(self, finished_goal_handle, result_future):
        if self.follow_goal_handle is not finished_goal_handle:
            return
        self.follow_goal_handle = None
        status = result_future.result().status
        if status == GoalStatus.STATUS_SUCCEEDED:
            self.report_reached_waypoints(len(self.followed_waypoint_sequences))
            self.get_logger().info('finished driving')
            return
        error_message = result_future.result().result.error_msg or 'no error message'
        self.get_logger().warning(f'driving ended with status {status}: {error_message}')


def main():
    rclpy.init()
    node = GroundStationBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
