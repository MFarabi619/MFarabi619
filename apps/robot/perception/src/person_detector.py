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
from ultralytics import YOLO
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)

PERSON_COLOR = Color(r=0.3, g=0.9, b=1.0, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

LABEL_MARGIN_PIXELS = 8.0
MILLIMETERS_PER_METER = 1000.0
MILLIMETER_DEPTH_ENCODING = '16UC1'
METER_DEPTH_ENCODING = '32FC1'
BYTES_PER_MILLIMETER_DEPTH_PIXEL = 2
BYTES_PER_METER_DEPTH_PIXEL = 4
LIVE_PARAMETERS = frozenset({'min_score'})


class PersonDetector(Node):
    def __init__(self):
        super().__init__('person_detector')
        self.image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed'
        ).value
        self.depth_topic = self.declare_parameter(
            'depth_topic', 'sensors/camera_0/depth/image_raw'
        ).value
        self.depth_camera_info_topic = self.declare_parameter(
            'depth_camera_info_topic', 'sensors/camera_0/depth/camera_info'
        ).value
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/vision/overlay'
        ).value
        model_path = self.declare_parameter(
            'model_path', 'perception/models/yolo26n.pt'
        ).value
        self.class_label = self.declare_parameter('class_label', 'person').value
        self.person_class_id = self.declare_parameter('person_class_id', 0).value
        self.min_score = self.declare_parameter('min_score', 0.5).value
        self.depth_sample_radius = self.declare_parameter('depth_sample_radius', 4).value
        self.depth_timeout = self.declare_parameter('depth_timeout', 0.5).value
        self.device = self.declare_parameter('device', 'mps').value
        self.tracker_config = self.declare_parameter(
            'tracker_config', 'perception/config/person_tracker.yaml').value

        self.model = YOLO(model_path)

        self.latest_depth = None
        self.latest_depth_time = None
        self.camera_model = None
        self.depth_frame_id = ''

        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(ImageAnnotations, overlay_topic, 10)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CameraInfo, self.depth_camera_info_topic, self.on_depth_camera_info,
            qos_profile_sensor_data
        )
        freshest_frame_qos = QoSProfile(
            depth=1, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.create_subscription(
            Image, self.depth_topic, self.on_depth, freshest_frame_qos
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, freshest_frame_qos
        )
        self.get_logger().info(
            f'{self.class_label} detector {model_path}: {self.image_topic}')

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
        self.latest_depth = depth
        self.latest_depth_time = self.get_clock().now()

    def on_image(self, message):
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        result = self.model.track(
            bgr, classes=[self.person_class_id], tracker=self.tracker_config,
            device=self.device, persist=True, verbose=False)[0]

        detections = Detection2DArray()
        detections.header.stamp = message.header.stamp
        detections.header.frame_id = self.depth_frame_id
        overlay = ImageAnnotations()
        for box in result.boxes:
            score = float(box.conf[0])
            if score < self.min_score:
                continue
            track_id = int(box.id.item()) if box.id is not None else None
            distance, point = self.bounding_box_range(box)
            detections.detections.append(
                self.detection(message.header.stamp, box, score, point, track_id))
            self.annotate(overlay, message.header.stamp, box, distance, track_id)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def bounding_box_range(self, box):
        if self.latest_depth is None or self.depth_is_stale():
            return None, None
        center_x_fraction, center_y_fraction = box.xywhn[0].tolist()[:2]
        depth_height, depth_width = self.latest_depth.shape[:2]
        depth_x = int(center_x_fraction * depth_width)
        depth_y = int(center_y_fraction * depth_height)
        radius = self.depth_sample_radius
        depth_patch = self.latest_depth[
            max(depth_y - radius, 0):depth_y + radius + 1,
            max(depth_x - radius, 0):depth_x + radius + 1,
        ]
        valid_depths = depth_patch[np.isfinite(depth_patch) & (depth_patch > 0)]
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
        return age > Duration(seconds=self.depth_timeout)

    def detection(self, stamp, box, score, point, track_id):
        center_x, center_y, box_width, box_height = box.xywh[0].tolist()
        detection = Detection2D()
        detection.header.stamp = stamp
        detection.header.frame_id = self.depth_frame_id
        detection.id = str(track_id) if track_id is not None else ''
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(x=center_x, y=center_y), theta=0.0),
            size_x=box_width,
            size_y=box_height,
        )
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = self.class_label
        hypothesis.hypothesis.score = score
        if point is not None:
            hypothesis.pose.pose.position = point
        detection.results.append(hypothesis)
        return detection

    def annotate(self, overlay, stamp, box, distance, track_id):
        left, top, right, bottom = box.xyxy[0].tolist()
        outline = PointsAnnotation()
        outline.timestamp = stamp
        outline.type = PointsAnnotation.LINE_LOOP
        outline.points = [
            Point2(x=left, y=top),
            Point2(x=right, y=top),
            Point2(x=right, y=bottom),
            Point2(x=left, y=bottom),
        ]
        outline.outline_color = PERSON_COLOR
        outline.thickness = 2.0
        overlay.points.append(outline)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(
            x=left, y=max(top - LABEL_MARGIN_PIXELS, 0.0))
        distance_text = f'{distance:.1f}m' if distance is not None else '?'
        identity_text = (
            f'{self.class_label} {track_id}' if track_id is not None
            else self.class_label)
        label.text = f'{identity_text} {distance_text}'
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
    node = PersonDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
