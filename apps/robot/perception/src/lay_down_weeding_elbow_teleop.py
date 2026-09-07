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
import os

import cv2
from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
from geometry_msgs.msg import TwistStamped
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool

MODEL_FILENAME = 'pose_landmarker_full.task'


def default_model_path():
    directory = os.path.dirname(__file__)
    alongside = os.path.join(directory, 'models', MODEL_FILENAME)
    if os.path.exists(alongside):
        return alongside
    return os.path.normpath(
        os.path.join(directory, '..', 'models', MODEL_FILENAME))


DEFAULT_MODEL_PATH = default_model_path()

ELBOW_LANDMARKS = {'left': 13, 'right': 14}

ZONE_FORWARD = 'forward'
ZONE_REVERSE = 'reverse'
ZONE_HOLD = 'hold'
CALIBRATING = 'calibrating'
OPERATOR_ABSENT = 'absent'

LIVE_PARAMETERS = frozenset({
    'forward_speed_mps', 'reverse_speed_mps', 'forward_threshold_fraction',
    'reverse_threshold_fraction', 'commit_frames', 'command_smoothing_seconds',
    'min_elbow_visibility', 'invert_drive_axis',
})
RECALIBRATING_PARAMETERS = frozenset({'drive_axis', 'arm_side'})

FORWARD_COLOR = Color(r=0.722, g=0.733, b=0.149, a=1.0)
REVERSE_COLOR = Color(r=0.996, g=0.502, b=0.098, a=1.0)
HOLD_COLOR = Color(r=0.984, g=0.286, b=0.204, a=1.0)
CALIBRATION_COLOR = Color(r=0.980, g=0.741, b=0.184, a=1.0)
BOUNDARY_COLOR = Color(r=0.980, g=0.741, b=0.184, a=0.85)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)
STATE_COLORS = {
    ZONE_FORWARD: FORWARD_COLOR,
    ZONE_REVERSE: REVERSE_COLOR,
    CALIBRATING: CALIBRATION_COLOR,
}
STATUS_FONT_SIZE = 24.0
BOUNDARY_THICKNESS = 2.0
ELBOW_MARKER_THICKNESS = 8.0


class LayDownWeedingElbowTeleop(Node):
    def __init__(self, **node_arguments):
        super().__init__('lay_down_weeding_elbow_teleop', **node_arguments)
        image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/weeding/elbow_overlay').value
        model_path = self.declare_parameter('model', DEFAULT_MODEL_PATH).value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.arm_side = self.declare_parameter('arm_side', 'either').value
        self.drive_axis = self.declare_parameter('drive_axis', 'y').value
        self.invert_drive_axis = self.declare_parameter(
            'invert_drive_axis', False).value
        self.forward_threshold_fraction = self.declare_parameter(
            'forward_threshold_fraction', 0.06).value
        self.reverse_threshold_fraction = self.declare_parameter(
            'reverse_threshold_fraction', 0.06).value
        self.forward_speed_mps = self.declare_parameter(
            'forward_speed_mps', 0.12).value
        self.reverse_speed_mps = self.declare_parameter(
            'reverse_speed_mps', 0.12).value
        self.commit_frames = self.declare_parameter('commit_frames', 5).value
        self.neutral_sample_frames = self.declare_parameter(
            'neutral_sample_frames', 10).value
        self.command_smoothing_seconds = self.declare_parameter(
            'command_smoothing_seconds', 0.4).value
        self.min_elbow_visibility = self.declare_parameter(
            'min_elbow_visibility', 0.5).value
        self.max_detections_per_second = self.declare_parameter(
            'max_detections_per_second', 10.0).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.landmarker = vision.PoseLandmarker.create_from_options(
            vision.PoseLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=model_path),
                running_mode=vision.RunningMode.VIDEO,
                num_poses=1))

        self.last_timestamp_ms = 0
        self.neutral_samples = []
        self.neutral_position = None
        self.tracked_side = None
        self.pending_zone = ZONE_HOLD
        self.zone_frames = 0
        self.smoothed_forward_speed = 0.0
        self.previous_drive_time_s = None
        self.previous_detection_time_s = None
        self.min_detection_interval_s = (
            1.0 / self.max_detections_per_second
            if self.max_detections_per_second > 0.0 else 0.0)

        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, cmd_vel_topic, 10)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            CompressedImage, image_topic, self.on_image, qos_profile_sensor_data)
        self.get_logger().info(
            f'lay-down weeding elbow teleop: {image_topic} -> {cmd_vel_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        self.reset_calibration()
        self.halt()
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)
            elif parameter.name in RECALIBRATING_PARAMETERS:
                setattr(self, parameter.name, parameter.value)
                self.reset_calibration()
                self.halt()

    def on_image(self, message):
        if not self.is_enabled:
            return
        if not self.claim_detection_slot():
            return
        rgb = cv2.imdecode(
            np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR_RGB)
        if rgb is None:
            self.halt()
            return
        stamp = message.header.stamp
        timestamp_ms = max(
            self.last_timestamp_ms + 1,
            stamp.sec * 1000 + stamp.nanosec // 1_000_000)
        self.last_timestamp_ms = timestamp_ms
        result = self.landmarker.detect_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp_ms)
        height, width = rgb.shape[:2]
        selected = self.select_elbow(result.pose_landmarks)
        if selected is None:
            if self.neutral_position is None:
                self.reset_calibration()
            self.halt()
            self.publish_overlay(stamp, None, OPERATOR_ABSENT, width, height)
            return
        side, elbow = selected
        position = elbow.x if self.drive_axis == 'x' else elbow.y
        if self.neutral_position is None:
            self.calibrate(side, position)
            self.halt()
            self.publish_overlay(stamp, elbow, CALIBRATING, width, height)
            return
        zone = self.classify(position)
        if zone == ZONE_HOLD:
            self.halt()
        else:
            self.creep(zone)
        self.publish_overlay(stamp, elbow, zone, width, height)

    def select_elbow(self, poses):
        if not poses:
            return None
        landmarks = poses[0]
        if self.tracked_side is not None:
            sides = [self.tracked_side]
        elif self.arm_side in ELBOW_LANDMARKS:
            sides = [self.arm_side]
        else:
            sides = list(ELBOW_LANDMARKS)
        visible_elbows = [
            (side, landmarks[ELBOW_LANDMARKS[side]]) for side in sides
            if landmarks[ELBOW_LANDMARKS[side]].visibility
            >= self.min_elbow_visibility]
        if not visible_elbows:
            return None
        return max(visible_elbows, key=lambda pair: pair[1].visibility)

    def calibrate(self, side, position):
        self.tracked_side = side
        self.neutral_samples.append(position)
        if len(self.neutral_samples) >= self.neutral_sample_frames:
            self.neutral_position = float(np.median(self.neutral_samples))
            self.neutral_samples.clear()

    def reset_calibration(self):
        self.neutral_samples.clear()
        self.neutral_position = None
        self.tracked_side = None

    def classify(self, position):
        displacement = position - self.neutral_position
        if self.invert_drive_axis:
            displacement = -displacement
        if displacement > self.forward_threshold_fraction:
            return ZONE_FORWARD
        if displacement < -self.reverse_threshold_fraction:
            return ZONE_REVERSE
        return ZONE_HOLD

    def creep(self, zone):
        if zone != self.pending_zone:
            self.pending_zone = zone
            self.zone_frames = 0
            self.smoothed_forward_speed = 0.0
            self.previous_drive_time_s = None
        self.zone_frames += 1
        if not self.is_creeping():
            self.publish(0.0)
            return
        if zone == ZONE_FORWARD:
            self.drive(self.forward_speed_mps)
        else:
            self.drive(-self.reverse_speed_mps)

    def is_creeping(self):
        return self.zone_frames >= self.commit_frames

    def claim_detection_slot(self):
        now_s = self.get_clock().now().nanoseconds * 1e-9
        previous_s = self.previous_detection_time_s
        if (previous_s is not None
                and now_s - previous_s < self.min_detection_interval_s):
            return False
        self.previous_detection_time_s = now_s
        return True

    def halt(self):
        self.pending_zone = ZONE_HOLD
        self.zone_frames = 0
        self.smoothed_forward_speed = 0.0
        self.previous_drive_time_s = None
        self.publish(0.0)

    def claim_smoothing_fraction(self):
        now_s = self.get_clock().now().nanoseconds * 1e-9
        previous_s = self.previous_drive_time_s
        self.previous_drive_time_s = now_s
        if self.command_smoothing_seconds <= 0.0 or previous_s is None:
            return 1.0
        return 1.0 - math.exp(-(now_s - previous_s) / self.command_smoothing_seconds)

    def drive(self, forward_speed):
        fraction = self.claim_smoothing_fraction()
        self.smoothed_forward_speed += fraction * (
            forward_speed - self.smoothed_forward_speed)
        self.publish(self.smoothed_forward_speed)

    def publish(self, forward_speed):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = float(forward_speed)
        self.cmd_vel_publisher.publish(message)

    def publish_overlay(self, stamp, elbow, state, width, height):
        overlay = ImageAnnotations()
        if self.neutral_position is not None:
            overlay.points.append(self.zone_boundaries(stamp, width, height))
        if elbow is not None:
            marker = PointsAnnotation()
            marker.timestamp = stamp
            marker.type = PointsAnnotation.POINTS
            marker.points = [Point2(x=elbow.x * width, y=elbow.y * height)]
            marker.outline_color = STATE_COLORS.get(state, HOLD_COLOR)
            marker.thickness = ELBOW_MARKER_THICKNESS
            overlay.points.append(marker)
        status = TextAnnotation()
        status.timestamp = stamp
        status.position = Point2(x=8.0, y=8.0)
        status.text = self.status_text(state)
        status.font_size = STATUS_FONT_SIZE
        status.text_color = TEXT_COLOR
        status.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(status)
        self.overlay_publisher.publish(overlay)

    def zone_boundaries(self, stamp, width, height):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LIST
        direction_sign = -1.0 if self.invert_drive_axis else 1.0
        boundaries = (
            self.neutral_position
            + self.forward_threshold_fraction * direction_sign,
            self.neutral_position
            - self.reverse_threshold_fraction * direction_sign,
        )
        points = []
        for boundary in boundaries:
            if self.drive_axis == 'x':
                points += [
                    Point2(x=boundary * width, y=0.0),
                    Point2(x=boundary * width, y=float(height)),
                ]
            else:
                points += [
                    Point2(x=0.0, y=boundary * height),
                    Point2(x=float(width), y=boundary * height),
                ]
        annotation.points = points
        annotation.outline_color = BOUNDARY_COLOR
        annotation.thickness = BOUNDARY_THICKNESS
        return annotation

    def status_text(self, state):
        if state == ZONE_FORWARD and self.is_creeping():
            return f'ELBOW ▲ FORWARD {self.smoothed_forward_speed:.2f} m/s'
        if state == ZONE_REVERSE and self.is_creeping():
            return f'ELBOW ▼ REVERSE {abs(self.smoothed_forward_speed):.2f} m/s'
        if state == CALIBRATING:
            return 'ELBOW … CALIBRATING (hold still)'
        if state == OPERATOR_ABSENT:
            return 'ELBOW ■ HOLD (no operator)'
        return 'ELBOW ■ HOLD'


def main():
    rclpy.init()
    node = LayDownWeedingElbowTeleop()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
