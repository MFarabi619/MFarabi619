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
from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, CompressedImage, Image
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)

CONE_CLASS = 'cone'
CONE_COLOR = Color(r=1.0, g=0.5, b=0.0, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

MORPHOLOGY_KERNEL = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
LABEL_MARGIN_PIXELS = 8.0
BRACKET_FRACTION = 0.25
MILLIMETERS_PER_METER = 1000.0
NANOSECONDS_PER_SECOND = 1e9
DEPTH_ENCODING = '16UC1'
LIVE_PARAMETERS = frozenset({
    'cone_hue_min', 'cone_hue_max', 'min_saturation', 'min_value',
    'min_cone_area', 'min_triangularity', 'min_aspect_ratio',
})


class ConeDetector(Node):
    def __init__(self):
        super().__init__('cone_detector')
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
        self.cone_hue_min = self.declare_parameter('cone_hue_min', 5.0).value
        self.cone_hue_max = self.declare_parameter('cone_hue_max', 22.0).value
        self.min_saturation = self.declare_parameter('min_saturation', 0.5).value
        self.min_value = self.declare_parameter('min_value', 0.35).value
        self.min_cone_area = self.declare_parameter('min_cone_area', 400).value
        self.min_triangularity = self.declare_parameter('min_triangularity', 0.6).value
        self.min_aspect_ratio = self.declare_parameter('min_aspect_ratio', 1.0).value
        self.depth_sample_radius = self.declare_parameter('depth_sample_radius', 4).value
        self.depth_timeout = self.declare_parameter('depth_timeout', 0.5).value

        self.latest_depth = None
        self.latest_depth_time = None
        self.camera_model = None
        self.depth_frame_id = ''

        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(ImageAnnotations, overlay_topic, 10)
        self.add_on_set_parameters_callback(self.on_set_parameters)
        self.create_subscription(
            CameraInfo, self.depth_camera_info_topic, self.on_depth_camera_info,
            qos_profile_sensor_data
        )
        self.create_subscription(
            Image, self.depth_topic, self.on_depth, qos_profile_sensor_data
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, qos_profile_sensor_data
        )
        self.get_logger().info(f'cone detector: {self.image_topic} -> {detections_topic}')

    def on_depth_camera_info(self, message):
        self.depth_frame_id = message.header.frame_id
        if self.camera_model is None:
            self.camera_model = PinholeCameraModel()
        self.camera_model.from_camera_info(message)

    def on_depth(self, message):
        if message.encoding != DEPTH_ENCODING:
            self.get_logger().warning(
                f'expected {DEPTH_ENCODING} depth, got {message.encoding}',
                throttle_duration_sec=5.0,
            )
            return
        depth = np.frombuffer(message.data, np.uint16).reshape(
            message.height, message.step // 2
        )[:, :message.width]
        if message.is_bigendian:
            depth = depth.byteswap()
        self.latest_depth = depth
        self.latest_depth_time = self.get_clock().now()

    def on_image(self, message):
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        height, width = bgr.shape[:2]

        detections = Detection2DArray()
        detections.header.stamp = message.header.stamp
        detections.header.frame_id = self.depth_frame_id
        overlay = ImageAnnotations()
        for bounding_box, triangularity in self.detect_cones(self.cone_mask(bgr)):
            distance, point = self.cone_range(bounding_box, width, height)
            detections.detections.append(
                self.detection(message.header.stamp, bounding_box, triangularity, point))
            self.annotate(overlay, message.header.stamp, bounding_box, distance)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def cone_mask(self, bgr):
        hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(
            hsv,
            (self.cone_hue_min, self.min_saturation * 255.0, self.min_value * 255.0),
            (self.cone_hue_max, 255.0, 255.0),
        )
        return cv2.morphologyEx(mask, cv2.MORPH_OPEN, MORPHOLOGY_KERNEL)

    def detect_cones(self, mask):
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cones = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < self.min_cone_area:
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
            cones.append(((x, y, w, h), triangularity))
        return cones

    def cone_range(self, bounding_box, color_width, color_height):
        if self.latest_depth is None or self.depth_is_stale():
            return None, None
        x, y, w, h = bounding_box
        depth_height, depth_width = self.latest_depth.shape[:2]
        depth_x = int((x + w / 2.0) / color_width * depth_width)
        depth_y = int((y + h / 2.0) / color_height * depth_height)
        radius = self.depth_sample_radius
        depth_patch = self.latest_depth[
            max(depth_y - radius, 0):depth_y + radius + 1,
            max(depth_x - radius, 0):depth_x + radius + 1,
        ]
        valid_depths = depth_patch[depth_patch > 0]
        if valid_depths.size == 0:
            return None, None
        distance = float(np.median(valid_depths)) / MILLIMETERS_PER_METER
        return distance, self.deproject(depth_x, depth_y, distance)

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
        return age.nanoseconds > self.depth_timeout * NANOSECONDS_PER_SECOND

    def detection(self, stamp, bounding_box, triangularity, point):
        x, y, w, h = bounding_box
        detection = Detection2D()
        detection.header.stamp = stamp
        detection.header.frame_id = self.depth_frame_id
        detection.id = CONE_CLASS
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(x=x + w / 2.0, y=y + h / 2.0), theta=0.0),
            size_x=float(w),
            size_y=float(h),
        )
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = CONE_CLASS
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
        brackets.outline_color = CONE_COLOR
        brackets.thickness = 3.0
        overlay.points.append(brackets)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(x=float(x), y=max(float(y) - LABEL_MARGIN_PIXELS, 0.0))
        distance_text = '?' if distance is None else f'{distance:.2f} m'
        label.text = f'cone {distance_text}'
        label.font_size = 18.0
        label.text_color = TEXT_COLOR
        label.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(label)

    def on_set_parameters(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)
        return SetParametersResult(successful=True)


def main():
    rclpy.init()
    node = ConeDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
