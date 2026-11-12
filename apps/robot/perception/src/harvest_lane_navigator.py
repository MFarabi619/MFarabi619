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
import time

import cv2
from foxglove_msgs.msg import (
    CircleAnnotation,
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
from geometry_msgs.msg import TwistStamped
from nav_msgs.msg import Odometry
import numpy as np
import rclpy
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from robot_platform_msgs.action import FollowRow
from sensor_msgs.msg import CameraInfo, CompressedImage, Image
from std_srvs.srv import SetBool

CENTERED_COLOR = Color(r=0.35, g=1.0, b=0.55, a=1.0)
DRIFTING_COLOR = Color(r=1.0, g=0.75, b=0.15, a=1.0)
OFF_ROW_COLOR = Color(r=1.0, g=0.3, b=0.25, a=1.0)
WHEEL_TRACK_COLOR = Color(r=0.95, g=0.95, b=0.95, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.55)
WHEEL_TRACK_WIDTH_METERS = 1.17
CORRIDOR_START_METERS = 0.6
CORRIDOR_STEP_METERS = 0.4
CORRIDOR_LENGTH_METERS = 4.0
CENTER_LINE_THICKNESS_PIXELS = 3.5
WHEEL_TRACK_THICKNESS_PIXELS = 2.5
RUNG_THICKNESS_PIXELS = 2.0
FULL_DRIFT_ERROR_METERS = 0.3
NEAR_ALPHA = 0.9
FAR_ALPHA = 0.25
ROW_LINE_THICKNESS_PIXELS = 3.0
NEAR_RING_DIAMETER_PIXELS = 18.0
FAR_RING_DIAMETER_PIXELS = 8.0
RING_THICKNESS_PIXELS = 2.5
RING_FILL_ALPHA_RATIO = 0.2
LABEL_MARGIN_PIXELS = 16.0
LABEL_FONT_SIZE_PIXELS = 20.0
MASK_THRESHOLD = 127
MILLIMETER_DEPTH_ENCODING = '16UC1'
METER_DEPTH_ENCODING = '32FC1'
BYTES_PER_MILLIMETER_DEPTH_PIXEL = 2
BYTES_PER_METER_DEPTH_PIXEL = 4
MILLIMETERS_PER_METER = 1000.0
NANOSECONDS_PER_SECOND = 1_000_000_000
STRIP_COUNT = 6
MIN_PIXELS_PER_STRIP = 30
MIN_VALID_STRIPS = 2
MAX_TRACKING_DISTANCE_METERS = 8.0
MIN_DEPTH_METERS = 0.3
MIN_PHASE_CONCENTRATION = 0.35
MAX_PHASE_RESIDUAL_METERS = 0.12
MAX_LATERAL_JUMP_METERS = 0.3
MAX_LATERAL_CORRECTION_METERS = 0.3
MIN_ROW_TRAVEL_METERS = 3.0
ALIGNED_HEADING_ERROR_RADIANS = math.radians(6.0)
PIVOT_HEADING_ERROR_RADIANS = math.radians(18.0)
ALIGNED_LATERAL_ERROR_METERS = 0.06
PIVOT_LATERAL_ERROR_METERS = 0.22
ROW_LOST_MISS_LIMIT = 12
GOAL_POLL_SECONDS = 0.05
LIVE_PARAMETERS = frozenset({
    'roi_top_fraction', 'row_pitch_meters', 'forward_speed_meters_per_second',
    'lateral_gain', 'heading_gain', 'max_angular_speed_radians_per_second',
    'max_forward_speed_meters_per_second', 'camera_lateral_offset_meters',
    'camera_height_meters', 'lateral_trim_meters', 'command_smoothing_seconds',
})


def finite_or(value, fallback):
    return value if math.isfinite(value) else fallback


def alignment_fraction(error, aligned_threshold, pivot_threshold):
    return float(np.clip(
        (pivot_threshold - abs(error)) / (pivot_threshold - aligned_threshold), 0.0, 1.0))


def blended(start, end, fraction):
    return Color(
        r=start.r + (end.r - start.r) * fraction,
        g=start.g + (end.g - start.g) * fraction,
        b=start.b + (end.b - start.b) * fraction,
        a=start.a + (end.a - start.a) * fraction)


def faded(color, alpha):
    return Color(r=color.r, g=color.g, b=color.b, a=float(alpha))


def error_color(lateral_error_meters):
    drift_fraction = min(abs(lateral_error_meters) / FULL_DRIFT_ERROR_METERS, 1.0)
    if drift_fraction < 0.5:
        return blended(CENTERED_COLOR, DRIFTING_COLOR, drift_fraction * 2.0)
    return blended(DRIFTING_COLOR, OFF_ROW_COLOR, drift_fraction * 2.0 - 1.0)


class HarvestLaneNavigator(Node):
    def __init__(self):
        super().__init__('harvest_lane_navigator')
        mask_topic = self.declare_parameter(
            'mask_topic', 'perception/canopy/mask/compressed').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/canopy/overlay').value
        camera_info_topic = self.declare_parameter(
            'camera_info_topic', 'sensors/camera_0/color/camera_info').value
        depth_topic = self.declare_parameter(
            'depth_topic', 'sensors/camera_0/depth/image_raw').value
        odom_topic = self.declare_parameter(
            'odom_topic', 'odom').value
        self.camera_lateral_offset_meters = self.declare_parameter(
            'camera_lateral_offset_meters', 0.5).value
        self.camera_height_meters = self.declare_parameter('camera_height_meters', 0.31).value
        self.lateral_trim_meters = self.declare_parameter('lateral_trim_meters', 0.0).value
        self.row_pitch_meters = self.declare_parameter('row_pitch_meters', 1.2).value
        self.roi_top_fraction = self.declare_parameter('roi_top_fraction', 0.5).value
        self.forward_speed_meters_per_second = self.declare_parameter(
            'forward_speed_meters_per_second', 0.4).value
        self.lateral_gain = self.declare_parameter('lateral_gain', 1.5).value
        self.heading_gain = self.declare_parameter('heading_gain', 1.2).value
        self.max_angular_speed_radians_per_second = self.declare_parameter(
            'max_angular_speed_radians_per_second', 0.8).value
        self.max_forward_speed_meters_per_second = self.declare_parameter(
            'max_forward_speed_meters_per_second', 1.0).value
        self.command_smoothing_seconds = self.declare_parameter(
            'command_smoothing_seconds', 0.0).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.camera_focal_columns = None
        self.camera_center_column = None
        self.camera_focal_rows = None
        self.camera_center_row = None
        self.depth_image = None
        self.goal_handle = None
        self.goal_distance_meters = 0.0
        self.goal_forward_speed_meters_per_second = 0.0
        self.distance_traveled_meters = 0.0
        self.previous_odometry_position = None
        self.row_miss_count = 0
        self.goal_outcome = None
        self.tracked_lateral_error_meters = None
        self.latest_angular_speed_radians_per_second = 0.0
        self.smoothed_forward_speed_meters_per_second = 0.0
        self.smoothed_angular_speed_radians_per_second = 0.0
        self.previous_drive_time_seconds = None
        self.fit_report = ''
        self.callback_group = ReentrantCallbackGroup()
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, 10)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CameraInfo, camera_info_topic, self.on_camera_info,
            qos_profile_sensor_data, callback_group=self.callback_group)
        self.create_subscription(
            Image, depth_topic, self.on_depth, qos_profile_sensor_data,
            callback_group=self.callback_group)
        self.create_subscription(
            Odometry, odom_topic, self.on_odometry, 10,
            callback_group=self.callback_group)
        self.create_subscription(
            CompressedImage, mask_topic, self.on_mask, qos_profile_sensor_data,
            callback_group=self.callback_group)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.action_server = ActionServer(
            self, FollowRow, 'follow_row',
            execute_callback=self.execute_follow_row,
            goal_callback=self.on_goal_request,
            cancel_callback=self.on_cancel_request,
            callback_group=self.callback_group)
        self.get_logger().info(f'harvest lane navigator: {mask_topic} -> {cmd_vel_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        self.tracked_lateral_error_meters = None
        self.row_miss_count = 0
        if not request.data:
            self.halt()
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_goal_request(self, request):
        if self.goal_handle is not None:
            return GoalResponse.REJECT
        return GoalResponse.ACCEPT

    def on_cancel_request(self, goal_handle):
        return CancelResponse.ACCEPT

    def execute_follow_row(self, goal_handle):
        self.goal_distance_meters = goal_handle.request.travel_distance_meters
        self.goal_forward_speed_meters_per_second = (
            goal_handle.request.forward_speed_meters_per_second)
        self.distance_traveled_meters = 0.0
        self.previous_odometry_position = None
        self.row_miss_count = 0
        self.goal_outcome = None
        self.tracked_lateral_error_meters = None
        self.goal_handle = goal_handle
        self.get_logger().info(
            f'follow_row goal: {self.goal_distance_meters:.1f} m')
        while rclpy.ok():
            if goal_handle.is_cancel_requested:
                self.goal_outcome = FollowRow.Result.OUTCOME_CANCELED
                break
            if self.goal_outcome is not None:
                break
            time.sleep(GOAL_POLL_SECONDS)
        self.goal_handle = None
        self.halt()
        result = FollowRow.Result()
        result.distance_traveled_meters = float(self.distance_traveled_meters)
        result.outcome = self.goal_outcome or FollowRow.Result.OUTCOME_CANCELED
        self.conclude(goal_handle, result.outcome)
        self.get_logger().info(
            f'follow_row done: {result.outcome} after '
            f'{result.distance_traveled_meters:.1f} m')
        return result

    def conclude(self, goal_handle, outcome):
        if outcome == FollowRow.Result.OUTCOME_DISTANCE_REACHED:
            goal_handle.succeed()
        elif (outcome == FollowRow.Result.OUTCOME_ROW_LOST
              and self.goal_distance_meters <= 0.0
              and self.distance_traveled_meters >= MIN_ROW_TRAVEL_METERS):
            goal_handle.succeed()
        elif outcome == FollowRow.Result.OUTCOME_CANCELED:
            goal_handle.canceled()
        else:
            goal_handle.abort()

    def on_odometry(self, message):
        if self.goal_handle is None:
            return
        position = message.pose.pose.position
        if self.previous_odometry_position is not None:
            self.distance_traveled_meters += math.hypot(
                position.x - self.previous_odometry_position[0],
                position.y - self.previous_odometry_position[1])
        self.previous_odometry_position = (position.x, position.y)
        if 0.0 < self.goal_distance_meters <= self.distance_traveled_meters:
            self.goal_outcome = FollowRow.Result.OUTCOME_DISTANCE_REACHED

    def depth_at_mask_resolution(self, shape):
        if self.depth_image is None:
            return None
        if self.depth_image.shape == shape:
            return self.depth_image
        return cv2.resize(
            self.depth_image, (shape[1], shape[0]), interpolation=cv2.INTER_NEAREST)

    def on_depth(self, message):
        # The Orbbec driver publishes 16UC1 millimetres, not 32FC1.
        if message.encoding == MILLIMETER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.uint16).reshape(
                message.height, message.step // BYTES_PER_MILLIMETER_DEPTH_PIXEL
            )[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
            self.depth_image = depth.astype(np.float32) / MILLIMETERS_PER_METER
        elif message.encoding == METER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.float32).reshape(
                message.height, message.step // BYTES_PER_METER_DEPTH_PIXEL
            )[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
            self.depth_image = depth

    def on_camera_info(self, message):
        self.camera_focal_columns = message.k[0]
        self.camera_center_column = message.k[2]
        self.camera_focal_rows = message.k[4]
        self.camera_center_row = message.k[5]

    def on_mask(self, message):
        mask = cv2.imdecode(
            np.frombuffer(message.data, np.uint8), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            return
        if self.camera_focal_columns is None:
            self.get_logger().info(
                'waiting for camera info', throttle_duration_sec=5.0)
            return
        fit = self.lattice_fit(mask)
        if fit is None:
            self.get_logger().info(
                f'no canopy rows in view: {self.fit_report}',
                throttle_duration_sec=5.0)
            self.overlay_publisher.publish(ImageAnnotations())
            self.row_miss_count += 1
            if self.row_miss_count >= ROW_LOST_MISS_LIMIT:
                self.tracked_lateral_error_meters = None
                if self.row_miss_count == ROW_LOST_MISS_LIMIT:
                    self.halt()
                if self.goal_handle is not None:
                    self.goal_outcome = FollowRow.Result.OUTCOME_ROW_LOST
            return
        lateral_error_meters, heading_error_radians, strip_points = fit
        self.overlay_publisher.publish(self.annotations(
            message, strip_points, lateral_error_meters, heading_error_radians))
        self.row_miss_count = 0
        if self.goal_handle is not None:
            feedback = FollowRow.Feedback()
            feedback.lateral_error_meters = float(lateral_error_meters)
            feedback.heading_error_radians = float(heading_error_radians)
            feedback.distance_traveled_meters = float(self.distance_traveled_meters)
            self.goal_handle.publish_feedback(feedback)
        if self.is_enabled or self.goal_handle is not None:
            self.latest_angular_speed_radians_per_second = self.steering(
                lateral_error_meters, heading_error_radians)
            self.drive(
                self.commanded_forward_speed(lateral_error_meters, heading_error_radians),
                self.latest_angular_speed_radians_per_second)

    def lattice_fit(self, mask):
        height, width = mask.shape
        roi_top = int(height * self.roi_top_fraction)
        strip_edges = np.linspace(roi_top, height, STRIP_COUNT + 1).astype(int)
        distances = []
        phases = []
        strip_points = []
        strip_reports = []
        self.fit_report = ''
        depth = self.depth_at_mask_resolution(mask.shape)
        if depth is None:
            self.get_logger().warning(
                'no depth: falling back to level-ground distances',
                throttle_duration_sec=10.0)
        for strip_top, strip_bottom in zip(strip_edges, strip_edges[1:]):
            pixel_rows, pixel_columns = np.nonzero(
                mask[strip_top:strip_bottom, :] > MASK_THRESHOLD)
            if depth is not None:
                depths = depth[pixel_rows + strip_top, pixel_columns]
                valid = (np.isfinite(depths) & (depths >= MIN_DEPTH_METERS)
                         & (depths <= MAX_TRACKING_DISTANCE_METERS))
                if valid.sum() < MIN_PIXELS_PER_STRIP:
                    strip_reports.append(f'{valid.sum()}px')
                    continue
                pixel_distances = depths[valid]
                pixel_columns = pixel_columns[valid]
            else:
                rows_below_center = pixel_rows + strip_top - self.camera_center_row
                valid = rows_below_center >= 1.0
                if valid.sum() < MIN_PIXELS_PER_STRIP:
                    strip_reports.append(f'{valid.sum()}px')
                    continue
                pixel_distances = (self.camera_focal_rows * self.camera_height_meters
                                   / rows_below_center[valid])
                near = pixel_distances <= MAX_TRACKING_DISTANCE_METERS
                if near.sum() < MIN_PIXELS_PER_STRIP:
                    strip_reports.append(f'{near.sum()}px-near')
                    continue
                pixel_distances = pixel_distances[near]
                pixel_columns = pixel_columns[valid][near]
            lateral_positions = self.camera_lateral_offset_meters - (
                (pixel_columns - self.camera_center_column)
                * pixel_distances / self.camera_focal_columns)
            angles = 2.0 * np.pi * lateral_positions / self.row_pitch_meters
            resultant = np.exp(1j * angles).mean()
            phase = float(np.angle(resultant)) * (
                self.row_pitch_meters / (2.0 * np.pi))
            strip_reports.append(
                f'{pixel_distances.size}px'
                f' R{abs(resultant):.2f} p{phase:+.2f}'
                f' d{float(pixel_distances.mean()):.1f}')
            if abs(resultant) < MIN_PHASE_CONCENTRATION:
                continue
            strip_distance = float(pixel_distances.mean())
            distances.append(strip_distance)
            phases.append(phase)
            strip_points.append((
                self.camera_center_column + self.camera_focal_columns
                * (self.camera_lateral_offset_meters - phase) / strip_distance,
                (strip_top + strip_bottom) / 2.0))
        if len(distances) < MIN_VALID_STRIPS:
            self.fit_report = (
                f'{len(distances)} valid strips'
                f' [{" | ".join(strip_reports)}]')
            return None
        near_to_far_order = np.argsort(distances)
        sorted_distances = np.asarray(distances)[near_to_far_order]
        sorted_unwrapped_phases = np.unwrap(
            np.asarray(phases)[near_to_far_order], period=self.row_pitch_meters)
        unwrapped_phases = np.empty_like(sorted_unwrapped_phases)
        unwrapped_phases[near_to_far_order] = sorted_unwrapped_phases
        strip_points = [
            (self.camera_center_column + self.camera_focal_columns
             * (self.camera_lateral_offset_meters - phase) / distance, row)
            for phase, distance, (_, row)
            in zip(unwrapped_phases, distances, strip_points)]
        phase_slope, phase_intercept = np.polyfit(
            sorted_distances, sorted_unwrapped_phases, 1)
        residuals = sorted_unwrapped_phases - (
            phase_slope * sorted_distances + phase_intercept)
        if np.abs(residuals).max() > MAX_PHASE_RESIDUAL_METERS:
            self.fit_report = (
                f'residual {np.abs(residuals).max():.2f}m'
                f' [{" | ".join(strip_reports)}]')
            return None
        lateral_error_meters = -float(phase_intercept + phase_slope * np.mean(distances))
        lateral_error_meters += self.lateral_trim_meters
        if self.tracked_lateral_error_meters is not None:
            lattice_shift_meters = self.row_pitch_meters * round(
                (self.tracked_lateral_error_meters - lateral_error_meters)
                / self.row_pitch_meters)
            lateral_error_meters += lattice_shift_meters
            lateral_jump_meters = lateral_error_meters - self.tracked_lateral_error_meters
            if abs(lateral_jump_meters) > MAX_LATERAL_JUMP_METERS:
                self.fit_report = (
                    f'lateral jump {lateral_jump_meters:+.2f}m'
                    f' [{" | ".join(strip_reports)}]')
                return None
        self.tracked_lateral_error_meters = lateral_error_meters
        heading_error_radians = float(math.atan(-phase_slope))
        return lateral_error_meters, heading_error_radians, strip_points

    def steering(self, lateral_error_meters, heading_error_radians):
        clamped_lateral_error_meters = float(np.clip(
            lateral_error_meters,
            -MAX_LATERAL_CORRECTION_METERS, MAX_LATERAL_CORRECTION_METERS))
        return float(np.clip(
            -(self.lateral_gain * clamped_lateral_error_meters
              + self.heading_gain * heading_error_radians),
            -self.max_angular_speed_radians_per_second,
            self.max_angular_speed_radians_per_second))

    def commanded_forward_speed(self, lateral_error_meters, heading_error_radians):
        if self.goal_handle is not None and self.goal_forward_speed_meters_per_second > 0.0:
            speed_meters_per_second = self.goal_forward_speed_meters_per_second
        else:
            speed_meters_per_second = self.forward_speed_meters_per_second
        return speed_meters_per_second * min(
            alignment_fraction(
                heading_error_radians,
                ALIGNED_HEADING_ERROR_RADIANS, PIVOT_HEADING_ERROR_RADIANS),
            alignment_fraction(
                lateral_error_meters,
                ALIGNED_LATERAL_ERROR_METERS, PIVOT_LATERAL_ERROR_METERS))

    def claim_smoothing_fraction(self):
        now_seconds = self.get_clock().now().nanoseconds / NANOSECONDS_PER_SECOND
        previous_seconds = self.previous_drive_time_seconds
        self.previous_drive_time_seconds = now_seconds
        if self.command_smoothing_seconds <= 0.0 or previous_seconds is None:
            return 1.0
        return 1.0 - math.exp(-(now_seconds - previous_seconds) / self.command_smoothing_seconds)

    def drive(self, forward_speed_meters_per_second, angular_speed_radians_per_second):
        fraction = self.claim_smoothing_fraction()
        self.smoothed_forward_speed_meters_per_second += fraction * (
            finite_or(forward_speed_meters_per_second, 0.0)
            - self.smoothed_forward_speed_meters_per_second)
        self.smoothed_angular_speed_radians_per_second += fraction * (
            finite_or(angular_speed_radians_per_second, 0.0)
            - self.smoothed_angular_speed_radians_per_second)
        # A non-finite command reaches the driver as a negative comparison and
        # selects the reverse branch, so every value is forced finite first.
        max_forward_speed_meters_per_second = max(
            finite_or(self.max_forward_speed_meters_per_second, 0.0), 0.0)
        max_angular_speed_radians_per_second = abs(
            finite_or(self.max_angular_speed_radians_per_second, 0.0))
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(np.clip(
            finite_or(self.smoothed_forward_speed_meters_per_second, 0.0),
            -max_forward_speed_meters_per_second, max_forward_speed_meters_per_second))
        message.twist.angular.z = float(np.clip(
            finite_or(self.smoothed_angular_speed_radians_per_second, 0.0),
            -max_angular_speed_radians_per_second, max_angular_speed_radians_per_second))
        self.cmd_vel_publisher.publish(message)

    def halt(self):
        self.latest_angular_speed_radians_per_second = 0.0
        self.smoothed_forward_speed_meters_per_second = 0.0
        self.smoothed_angular_speed_radians_per_second = 0.0
        self.previous_drive_time_seconds = None
        self.drive(0.0, 0.0)

    def ground_pixel(self, distance, lateral):
        return Point2(
            x=float(self.camera_center_column + self.camera_focal_columns
                    * (self.camera_lateral_offset_meters - lateral) / distance),
            y=float(self.camera_center_row + self.camera_focal_rows
                    * self.camera_height_meters / distance))

    def corridor(self, stamp, lateral_error_meters, heading_error_radians, color):
        distances = np.arange(
            CORRIDOR_START_METERS, CORRIDOR_START_METERS + CORRIDOR_LENGTH_METERS,
            CORRIDOR_STEP_METERS)
        row_slope = math.tan(-heading_error_radians)
        centers = -lateral_error_meters + row_slope * distances
        alphas = np.linspace(NEAR_ALPHA, FAR_ALPHA, distances.size)
        pieces = []
        for lateral_offset_meters, line_color, thickness in (
                (0.0, color, CENTER_LINE_THICKNESS_PIXELS),
                (WHEEL_TRACK_WIDTH_METERS / 2.0,
                 WHEEL_TRACK_COLOR, WHEEL_TRACK_THICKNESS_PIXELS),
                (-WHEEL_TRACK_WIDTH_METERS / 2.0,
                 WHEEL_TRACK_COLOR, WHEEL_TRACK_THICKNESS_PIXELS)):
            line = PointsAnnotation()
            line.timestamp = stamp
            line.type = PointsAnnotation.LINE_STRIP
            line.thickness = thickness
            line.outline_color = line_color
            line.points = [
                self.ground_pixel(distance, center + lateral_offset_meters)
                for distance, center in zip(distances, centers)]
            line.outline_colors = [faded(line_color, alpha) for alpha in alphas]
            pieces.append(line)
        rungs = PointsAnnotation()
        rungs.timestamp = stamp
        rungs.type = PointsAnnotation.LINE_LIST
        rungs.thickness = RUNG_THICKNESS_PIXELS
        rungs.outline_color = WHEEL_TRACK_COLOR
        for distance, center, alpha in zip(distances, centers, alphas):
            rungs.points.append(
                self.ground_pixel(distance, center + WHEEL_TRACK_WIDTH_METERS / 2.0))
            rungs.points.append(
                self.ground_pixel(distance, center - WHEEL_TRACK_WIDTH_METERS / 2.0))
            rungs.outline_colors.append(faded(WHEEL_TRACK_COLOR, alpha))
        pieces.append(rungs)
        return pieces

    def annotations(self, message, strip_points, lateral_error_meters, heading_error_radians):
        overlay = ImageAnnotations()
        color = error_color(lateral_error_meters)
        overlay.points.extend(self.corridor(
            message.header.stamp, lateral_error_meters, heading_error_radians, color))
        alphas = np.linspace(FAR_ALPHA, NEAR_ALPHA, len(strip_points))
        line = PointsAnnotation()
        line.timestamp = message.header.stamp
        line.type = PointsAnnotation.LINE_STRIP
        line.points = [Point2(x=float(column), y=float(row))
                       for column, row in strip_points]
        line.thickness = ROW_LINE_THICKNESS_PIXELS
        line.outline_color = color
        line.outline_colors = [faded(color, alpha) for alpha in alphas]
        overlay.points.append(line)
        diameters = np.linspace(
            FAR_RING_DIAMETER_PIXELS, NEAR_RING_DIAMETER_PIXELS, len(strip_points))
        for (column, row), alpha, diameter in zip(strip_points, alphas, diameters):
            ring = CircleAnnotation()
            ring.timestamp = message.header.stamp
            ring.position = Point2(x=float(column), y=float(row))
            ring.diameter = float(diameter)
            ring.thickness = RING_THICKNESS_PIXELS
            ring.outline_color = faded(color, alpha)
            ring.fill_color = faded(color, alpha * RING_FILL_ALPHA_RATIO)
            overlay.circles.append(ring)
        near_column, near_row = strip_points[-1]
        label = TextAnnotation()
        label.timestamp = message.header.stamp
        label.position = Point2(
            x=float(near_column) + LABEL_MARGIN_PIXELS,
            y=float(near_row) - LABEL_MARGIN_PIXELS)
        label.text = f'{lateral_error_meters:+.2f}m'
        label.font_size = LABEL_FONT_SIZE_PIXELS
        label.text_color = faded(color, 1.0)
        label.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(label)
        return overlay

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)


def main():
    rclpy.init()
    node = HarvestLaneNavigator()
    executor = rclpy.executors.MultiThreadedExecutor()
    try:
        rclpy.spin(node, executor=executor)
    except KeyboardInterrupt:
        pass
    finally:
        if rclpy.ok():
            node.halt()
            rclpy.shutdown()
        node.destroy_node()


if __name__ == '__main__':
    main()
