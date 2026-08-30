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
from foxglove_msgs.msg import Color, ImageAnnotations, Point2, PointsAnnotation, TextAnnotation
from geometry_msgs.msg import TwistStamped
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
import numpy as np
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, CompressedImage, Image
from std_srvs.srv import SetBool
from tf2_ros import Buffer, TransformListener

MILLIMETERS_PER_METER = 1000.0
MILLIMETER_DEPTH_ENCODING = '16UC1'
METER_DEPTH_ENCODING = '32FC1'
TRANSFORM_TIMEOUT = Duration(seconds=0.5)
BODY_SKIN_CLASS = 2
MIN_SKIN_PIXELS = 60
MIN_CLEARANCE_SAMPLES = 60
MIN_REGION_AREA_PIXELS = 60
CLEARANCE_PERCENTILE = 10.0
MAX_CLEARANCE_METERS = 10.0

SKIN_ABSENT = 'absent'
SKIN_UNMEASURED = 'unmeasured'
SKIN_LIFTED = 'lifted'
SKIN_GROUNDED = 'grounded'

LIVE_PARAMETERS = frozenset({
    'lift_clearance_meters', 'creep_speed_mps', 'commit_frames',
    'allow_creep_without_skin', 'command_smoothing_seconds', 'depth_timeout_seconds',
})

LIFTED_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
GROUNDED_COLOR = Color(r=1.0, g=0.3, b=0.2, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)
STATUS_FONT_SIZE = 24.0
LABEL_FONT_SIZE = 16.0
LABEL_MARGIN_PIXELS = 22.0
CENTIMETERS_PER_METER = 100.0

DEFAULT_MODEL_PATH = os.path.normpath(os.path.join(
    os.path.dirname(__file__), '..', 'models', 'selfie_multiclass_256x256.tflite'))


class WeedingCreep(Node):
    def __init__(self):
        super().__init__('weeding_creep')
        image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed').value
        depth_topic = self.declare_parameter(
            'depth_topic', 'sensors/camera_0/depth/image_raw').value
        depth_camera_info_topic = self.declare_parameter(
            'depth_camera_info_topic', 'sensors/camera_0/depth/camera_info').value
        cmd_vel_topic = self.declare_parameter('cmd_vel_topic', 'cmd_vel').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/weeding/overlay').value
        model_path = self.declare_parameter('model', DEFAULT_MODEL_PATH).value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.ground_frame = self.declare_parameter('ground_frame', 'base_footprint').value
        self.lift_clearance_meters = self.declare_parameter(
            'lift_clearance_meters', 0.08).value
        self.creep_speed_mps = self.declare_parameter('creep_speed_mps', 0.12).value
        self.commit_frames = self.declare_parameter('commit_frames', 5).value
        self.command_smoothing_seconds = self.declare_parameter(
            'command_smoothing_seconds', 0.4).value
        self.max_segmentations_per_second = self.declare_parameter(
            'max_segmentations_per_second', 10.0).value
        self.allow_creep_without_skin = self.declare_parameter(
            'allow_creep_without_skin', False).value
        self.depth_timeout_seconds = self.declare_parameter(
            'depth_timeout_seconds', 0.5).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.segmenter = vision.ImageSegmenter.create_from_options(
            vision.ImageSegmenterOptions(
                base_options=mp_python.BaseOptions(model_asset_path=model_path),
                output_confidence_masks=False,
                output_category_mask=True))

        self.latest_depth_meters = None
        self.latest_depth_time = None
        self.depth_frame_id = ''
        self.depth_intrinsics = None
        self.ground_depth_map = None
        self.lifted_frames = 0
        self.smoothed_forward_speed = 0.0
        self.previous_drive_time_s = None
        self.previous_segmentation_time_s = None
        self.min_segmentation_interval_s = (
            1.0 / self.max_segmentations_per_second
            if self.max_segmentations_per_second > 0.0 else 0.0)

        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)
        self.cmd_vel_publisher = self.create_publisher(TwistStamped, cmd_vel_topic, 10)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_service(SetBool, '~/enable', self.on_enable)
        freshest_frame = QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.create_subscription(
            CameraInfo, depth_camera_info_topic, self.on_depth_camera_info,
            qos_profile_sensor_data)
        self.create_subscription(Image, depth_topic, self.on_depth, freshest_frame)
        self.create_subscription(
            CompressedImage, image_topic, self.on_image, freshest_frame)
        self.get_logger().info(f'weeding creep: {image_topic} -> {cmd_vel_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        if not request.data:
            self.halt()
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)

    def on_depth_camera_info(self, message):
        if self.depth_intrinsics is None:
            self.depth_frame_id = message.header.frame_id
            self.depth_intrinsics = (
                message.k[0], message.k[4], message.k[2], message.k[5],
                message.width, message.height)

    def on_depth(self, message):
        if message.encoding == MILLIMETER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.uint16).reshape(
                message.height, message.step // 2)[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
            self.latest_depth_meters = depth.astype(np.float32) / MILLIMETERS_PER_METER
            self.latest_depth_time = self.get_clock().now()
        elif message.encoding == METER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.float32).reshape(
                message.height, message.step // 4)[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
            self.latest_depth_meters = depth
            self.latest_depth_time = self.get_clock().now()
        else:
            self.get_logger().warning(
                f'expected {MILLIMETER_DEPTH_ENCODING} or {METER_DEPTH_ENCODING}'
                f' depth, got {message.encoding}',
                throttle_duration_sec=5.0)

    def compute_ground_depth_map(self):
        if self.depth_intrinsics is None:
            return None
        try:
            transform = self.tf_buffer.lookup_transform(
                self.depth_frame_id, self.ground_frame, rclpy.time.Time(),
                timeout=TRANSFORM_TIMEOUT)
        except Exception as error:
            self.get_logger().warning(
                f'ground transform failed: {error}', throttle_duration_sec=5.0)
            return None
        translation = transform.transform.translation
        rotation = transform.transform.rotation
        qx, qy, qz, qw = rotation.x, rotation.y, rotation.z, rotation.w
        ground_normal = np.array([
            2.0 * (qx * qz + qw * qy),
            2.0 * (qy * qz - qw * qx),
            1.0 - 2.0 * (qx * qx + qy * qy),
        ])
        ground_origin = np.array([translation.x, translation.y, translation.z])
        fx, fy, cx, cy, width, height = self.depth_intrinsics
        columns, rows = np.meshgrid(np.arange(width), np.arange(height))
        rays = np.stack([
            (columns - cx) / fx,
            (rows - cy) / fy,
            np.ones_like(columns, dtype=np.float64),
        ], axis=-1)
        denominators = rays @ ground_normal
        numerator = float(ground_normal @ ground_origin)
        with np.errstate(divide='ignore', invalid='ignore'):
            ground_depth_map = numerator / denominators
        ground_depth_map[
            ~np.isfinite(ground_depth_map) | (ground_depth_map <= 0.0)] = np.inf
        return ground_depth_map.astype(np.float32)

    def on_image(self, message):
        if not self.is_enabled:
            return
        if not self.claim_segmentation_slot():
            return
        if self.ground_depth_map is None:
            self.ground_depth_map = self.compute_ground_depth_map()
        if (self.latest_depth_meters is None or self.ground_depth_map is None
                or self.depth_is_stale()):
            self.halt()
            return
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mask = np.squeeze(self.segmenter.segment(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ).category_mask.numpy_view())
        skin = mask == BODY_SKIN_CLASS

        depth = self.latest_depth_meters
        depth_height, depth_width = depth.shape[:2]
        skin_at_depth = cv2.resize(
            skin.astype(np.uint8), (depth_width, depth_height),
            interpolation=cv2.INTER_NEAREST).astype(bool)
        measurable_skin = skin_at_depth & np.isfinite(depth) & (depth > 0.0)
        clearances = self.ground_depth_map[measurable_skin] - depth[measurable_skin]

        color_height, color_width = rgb.shape[:2]
        if int(skin.sum()) < MIN_SKIN_PIXELS:
            skin_state = SKIN_ABSENT
            low_clearance = None
        elif clearances.size < MIN_CLEARANCE_SAMPLES:
            skin_state = SKIN_UNMEASURED
            low_clearance = None
        else:
            low_clearance = float(np.percentile(
                np.minimum(clearances, MAX_CLEARANCE_METERS), CLEARANCE_PERCENTILE))
            skin_state = (
                SKIN_LIFTED if low_clearance > self.lift_clearance_meters
                else SKIN_GROUNDED)

        can_creep = (
            skin_state == SKIN_LIFTED
            or (skin_state == SKIN_ABSENT and self.allow_creep_without_skin))
        if can_creep:
            self.lifted_frames += 1
            if self.is_creeping():
                self.drive(self.creep_speed_mps)
        else:
            self.halt()
        self.publish_overlay(message.header.stamp, skin, skin_state, low_clearance,
                             color_width, color_height)

    def publish_overlay(self, stamp, skin, skin_state, low_clearance, width, height):
        overlay = ImageAnnotations()
        state_color = LIFTED_COLOR if skin_state == SKIN_LIFTED else GROUNDED_COLOR
        _, _, region_stats, _ = cv2.connectedComponentsWithStats(
            skin.astype(np.uint8))
        mask_height, mask_width = skin.shape[:2]
        for x, y, w, h, area in region_stats[1:]:
            if area < MIN_REGION_AREA_PIXELS:
                continue
            box = PointsAnnotation()
            box.timestamp = stamp
            box.type = PointsAnnotation.LINE_LOOP
            box.points = [
                Point2(x=x * width / mask_width, y=y * height / mask_height),
                Point2(x=(x + w) * width / mask_width, y=y * height / mask_height),
                Point2(x=(x + w) * width / mask_width, y=(y + h) * height / mask_height),
                Point2(x=x * width / mask_width, y=(y + h) * height / mask_height),
            ]
            box.outline_color = state_color
            box.thickness = 3.0
            overlay.points.append(box)
        if low_clearance is not None and overlay.points:
            clearance_label = TextAnnotation()
            clearance_label.timestamp = stamp
            clearance_label.position = Point2(
                x=overlay.points[0].points[0].x,
                y=max(overlay.points[0].points[0].y - LABEL_MARGIN_PIXELS, 0.0))
            clearance_label.text = f'{low_clearance * CENTIMETERS_PER_METER:.0f}cm'
            clearance_label.font_size = LABEL_FONT_SIZE
            clearance_label.text_color = state_color
            clearance_label.background_color = TEXT_BACKGROUND_COLOR
            overlay.texts.append(clearance_label)

        status = TextAnnotation()
        status.timestamp = stamp
        status.position = Point2(x=8.0, y=8.0)
        if self.is_creeping():
            status.text = f'WEEDING ▲ CREEP {self.smoothed_forward_speed:.2f} m/s'
        elif skin_state == SKIN_GROUNDED:
            status.text = 'WEEDING ■ HOLD (hands down)'
        elif skin_state == SKIN_ABSENT:
            status.text = 'WEEDING ■ HOLD (no hands)'
        elif skin_state == SKIN_UNMEASURED:
            status.text = 'WEEDING ■ HOLD (no depth)'
        else:
            status.text = 'WEEDING ■ HOLD'
        status.font_size = STATUS_FONT_SIZE
        status.text_color = TEXT_COLOR
        status.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(status)
        self.overlay_publisher.publish(overlay)

    def claim_segmentation_slot(self):
        now_s = self.get_clock().now().nanoseconds * 1e-9
        previous_s = self.previous_segmentation_time_s
        if (previous_s is not None
                and now_s - previous_s < self.min_segmentation_interval_s):
            return False
        self.previous_segmentation_time_s = now_s
        return True

    def is_creeping(self):
        return self.lifted_frames >= self.commit_frames

    def depth_is_stale(self):
        if self.latest_depth_time is None:
            return True
        age = self.get_clock().now() - self.latest_depth_time
        return age > Duration(seconds=self.depth_timeout_seconds)

    def halt(self):
        self.lifted_frames = 0
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


def main():
    rclpy.init()
    node = WeedingCreep()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
