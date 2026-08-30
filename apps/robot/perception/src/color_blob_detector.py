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


import cv2
from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
from geometry_msgs.msg import Point
from image_geometry import PinholeCameraModel
import numpy as np
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import (
    QoSProfile,
    ReliabilityPolicy,
    qos_profile_sensor_data,
)
from sensor_msgs.msg import CameraInfo, CompressedImage, Image
from std_srvs.srv import SetBool
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)

BLOB_COLOR = Color(r=1.0, g=0.5, b=0.0, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

DENOISE_KERNEL = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
MERGE_KERNEL = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
LABEL_MARGIN_PIXELS = 8.0
BRACKET_FRACTION = 0.25
MILLIMETERS_PER_METER = 1000.0
MILLIMETER_DEPTH_ENCODING = '16UC1'
METER_DEPTH_ENCODING = '32FC1'
BYTES_PER_MILLIMETER_DEPTH_PIXEL = 2
BYTES_PER_METER_DEPTH_PIXEL = 4
LIVE_PARAMETERS = frozenset({
    'hue_min', 'hue_max', 'min_saturation', 'max_saturation', 'min_value',
    'max_value', 'min_area', 'min_triangularity', 'min_aspect_ratio',
    'fallback_range', 'max_fallback_box_fraction', 'roi_top_fraction',
})


class ColorBlobDetector(Node):
    def __init__(self):
        super().__init__('color_blob_detector')
        self.image_topic = self.declare_parameter(
            'image_topic', '/sensors/camera_0/color/image_raw/compressed'
        ).value
        self.depth_topic = self.declare_parameter(
            'depth_topic', '/sensors/camera_0/depth/image_raw'
        ).value
        self.depth_camera_info_topic = self.declare_parameter(
            'depth_camera_info_topic', '/sensors/camera_0/depth/camera_info'
        ).value
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/vision/overlay'
        ).value
        self.class_label = self.declare_parameter('class_label', 'blob').value
        self.is_enabled = self.declare_parameter('start_enabled', False).value
        self.hue_min = self.declare_parameter('hue_min', 5.0).value
        self.hue_max = self.declare_parameter('hue_max', 22.0).value
        self.min_saturation = self.declare_parameter('min_saturation', 0.5).value
        self.max_saturation = self.declare_parameter('max_saturation', 1.0).value
        self.min_value = self.declare_parameter('min_value', 0.35).value
        self.max_value = self.declare_parameter('max_value', 1.0).value
        self.min_area = self.declare_parameter('min_area', 400).value
        self.min_triangularity = self.declare_parameter('min_triangularity', 0.6).value
        self.min_aspect_ratio = self.declare_parameter('min_aspect_ratio', 1.0).value
        self.depth_sample_radius = self.declare_parameter('depth_sample_radius', 4).value
        self.depth_timeout_seconds = self.declare_parameter(
            'depth_timeout_seconds', 0.5).value
        self.fallback_range = self.declare_parameter('fallback_range', 0.0).value
        self.max_fallback_box_fraction = self.declare_parameter(
            'max_fallback_box_fraction', 0.25
        ).value
        self.roi_top_fraction = self.declare_parameter('roi_top_fraction', 0.0).value

        self.latest_depth_millimeters = None
        self.latest_depth_time = None
        self.camera_model = None
        self.depth_frame_id = ''

        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(ImageAnnotations, overlay_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            CameraInfo, self.depth_camera_info_topic, self.on_depth_camera_info,
            qos_profile_sensor_data
        )
        freshest_frame = QoSProfile(
            depth=1, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.create_subscription(
            Image, self.depth_topic, self.on_depth, freshest_frame
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, freshest_frame
        )
        self.get_logger().info(
            f'{self.class_label} detector: {self.image_topic} -> {detections_topic}')

    def on_depth_camera_info(self, message):
        self.depth_frame_id = message.header.frame_id
        if self.camera_model is None:
            self.camera_model = PinholeCameraModel()
        self.camera_model.from_camera_info(message)

    def on_depth(self, message):
        if message.encoding == MILLIMETER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.uint16).reshape(
                message.height, message.step // BYTES_PER_MILLIMETER_DEPTH_PIXEL
            )[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
        elif message.encoding == METER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.float32).reshape(
                message.height, message.step // BYTES_PER_METER_DEPTH_PIXEL
            )[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
            depth = depth * MILLIMETERS_PER_METER
        else:
            self.get_logger().warning(
                f'expected {MILLIMETER_DEPTH_ENCODING} or {METER_DEPTH_ENCODING}'
                f' depth, got {message.encoding}',
                throttle_duration_sec=5.0,
            )
            return
        self.latest_depth_millimeters = depth
        self.latest_depth_time = self.get_clock().now()

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_image(self, message):
        if not self.is_enabled:
            return
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        height, width = bgr.shape[:2]

        detections = Detection2DArray()
        detections.header.stamp = message.header.stamp
        detections.header.frame_id = self.depth_frame_id
        overlay = ImageAnnotations()
        for bounding_box, triangularity in self.detect_blobs(self.blob_mask(bgr)):
            distance, point = self.bounding_box_range(bounding_box, width, height)
            if point is None:
                point = self.fallback_point(bounding_box, width, height)
            detections.detections.append(
                self.detection(message.header.stamp, bounding_box, triangularity, point))
            self.annotate(overlay, message.header.stamp, bounding_box, distance)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def blob_mask(self, bgr):
        hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(
            hsv,
            (self.hue_min, self.min_saturation * 255.0, self.min_value * 255.0),
            (self.hue_max, self.max_saturation * 255.0, self.max_value * 255.0),
        )
        mask[:int(self.roi_top_fraction * mask.shape[0])] = 0
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, DENOISE_KERNEL)
        return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, MERGE_KERNEL)

    def detect_blobs(self, mask):
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        blobs = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < self.min_area:
                continue
            triangle_area, _ = cv2.minEnclosingTriangle(contour)
            if triangle_area <= 0.0:
                continue
            triangularity = area / triangle_area
            if triangularity < self.min_triangularity:
                continue
            x, y, w, h = cv2.boundingRect(contour)
            if h / w < self.min_aspect_ratio:
                continue
            blobs.append(((x, y, w, h), triangularity))
        return blobs

    def bounding_box_range(self, bounding_box, color_width, color_height):
        if self.latest_depth_millimeters is None or self.depth_is_stale():
            return None, None
        x, y, w, h = bounding_box
        depth_height, depth_width = self.latest_depth_millimeters.shape[:2]
        depth_x = int((x + w / 2.0) / color_width * depth_width)
        depth_y = int((y + h / 2.0) / color_height * depth_height)
        radius = self.depth_sample_radius
        depth_patch = self.latest_depth_millimeters[
            max(depth_y - radius, 0):depth_y + radius + 1,
            max(depth_x - radius, 0):depth_x + radius + 1,
        ]
        valid_depths = depth_patch[np.isfinite(depth_patch) & (depth_patch > 0)]
        if valid_depths.size == 0:
            return None, None
        distance = float(np.median(valid_depths)) / MILLIMETERS_PER_METER
        return distance, self.deproject(depth_x, depth_y, distance)

    def fallback_point(self, bounding_box, color_width, color_height):
        if self.fallback_range <= 0.0 or self.camera_model is None:
            return None
        x, y, w, h = bounding_box
        if max(w / color_width, h / color_height) > self.max_fallback_box_fraction:
            return None
        depth_x = int((x + w / 2.0) / color_width * self.camera_model.width)
        depth_y = int((y + h / 2.0) / color_height * self.camera_model.height)
        return self.deproject(depth_x, depth_y, self.fallback_range)

    def deproject(self, depth_x, depth_y, distance):
        if self.camera_model is None:
            return None
        ray_x, ray_y, ray_z = self.camera_model.project_pixel_to_3d_ray((depth_x, depth_y))
        return Point(
            x=ray_x / ray_z * distance,
            y=ray_y / ray_z * distance,
            z=distance,
        )

    def depth_is_stale(self):
        if self.latest_depth_time is None:
            return True
        age = self.get_clock().now() - self.latest_depth_time
        return age > Duration(seconds=self.depth_timeout_seconds)

    def detection(self, stamp, bounding_box, triangularity, point):
        x, y, w, h = bounding_box
        detection = Detection2D()
        detection.header.stamp = stamp
        detection.header.frame_id = self.depth_frame_id
        detection.id = self.class_label
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(x=x + w / 2.0, y=y + h / 2.0), theta=0.0),
            size_x=float(w),
            size_y=float(h),
        )
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = self.class_label
        hypothesis.hypothesis.score = float(triangularity)
        if point is not None:
            hypothesis.pose.pose.position = point
        detection.results.append(hypothesis)
        return detection

    def annotate(self, overlay, stamp, bounding_box, distance):
        x, y, w, h = bounding_box
        left, right, top, bottom = float(x), float(x + w), float(y), float(y + h)
        bracket = BRACKET_FRACTION * min(w, h)
        brackets = PointsAnnotation()
        brackets.timestamp = stamp
        brackets.type = PointsAnnotation.LINE_LIST
        brackets.points = [
            Point2(x=left, y=top), Point2(x=left + bracket, y=top),
            Point2(x=left, y=top), Point2(x=left, y=top + bracket),
            Point2(x=right, y=top), Point2(x=right - bracket, y=top),
            Point2(x=right, y=top), Point2(x=right, y=top + bracket),
            Point2(x=right, y=bottom), Point2(x=right - bracket, y=bottom),
            Point2(x=right, y=bottom), Point2(x=right, y=bottom - bracket),
            Point2(x=left, y=bottom), Point2(x=left + bracket, y=bottom),
            Point2(x=left, y=bottom), Point2(x=left, y=bottom - bracket),
        ]
        brackets.outline_color = BLOB_COLOR
        brackets.thickness = 3.0
        overlay.points.append(brackets)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(x=float(x), y=max(float(y) - LABEL_MARGIN_PIXELS, 0.0))
        distance_text = '?' if distance is None else f'{distance:.2f} m'
        label.text = f'{self.class_label} {distance_text}'
        label.font_size = 18.0
        label.text_color = TEXT_COLOR
        label.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(label)

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)


def main():
    rclpy.init()
    node = ColorBlobDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
