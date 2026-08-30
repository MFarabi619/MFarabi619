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
import onnxruntime
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

PERSON_COLOR = Color(r=0.3, g=0.9, b=1.0, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

LABEL_MARGIN_PIXELS = 8.0
MILLIMETERS_PER_METER = 1000.0
MILLIMETER_DEPTH_ENCODING = '16UC1'
METER_DEPTH_ENCODING = '32FC1'
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
            'model_path', 'perception/models/ssd_mobilenet_v1_12.onnx'
        ).value
        self.class_label = self.declare_parameter('class_label', 'person').value
        self.person_class_id = self.declare_parameter('person_class_id', 1).value
        self.min_score = self.declare_parameter('min_score', 0.5).value
        self.depth_sample_radius = self.declare_parameter('depth_sample_radius', 4).value
        self.depth_timeout_seconds = self.declare_parameter(
            'depth_timeout_seconds', 0.5).value
        inference_threads = self.declare_parameter('inference_threads', 2).value
        self.max_detections_per_second = self.declare_parameter('max_detections_per_second', 10.0).value
        self.min_detection_interval = (
            Duration(seconds=1.0 / self.max_detections_per_second)
            if self.max_detections_per_second > 0.0 else Duration())
        self.previous_detection_time = None
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        session_options = onnxruntime.SessionOptions()
        session_options.intra_op_num_threads = inference_threads
        self.session = onnxruntime.InferenceSession(
            model_path, session_options, providers=['CPUExecutionProvider'])
        self.input_name = self.session.get_inputs()[0].name

        self.latest_depth_millimeters = None
        self.latest_depth_time = None
        self.camera_model = None
        self.depth_frame_id = ''

        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(ImageAnnotations, overlay_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CameraInfo, self.depth_camera_info_topic, self.on_depth_camera_info,
            qos_profile_sensor_data
        )
        freshest_frame = QoSProfile(
            depth=1, reliability=ReliabilityPolicy.BEST_EFFORT)
        self.create_subscription(
            Image, self.depth_topic, self.on_depth, freshest_frame
        )
        if self.image_topic.endswith('/compressed'):
            self.create_subscription(
                CompressedImage, self.image_topic, self.on_compressed_image, freshest_frame
            )
        else:
            self.create_subscription(
                Image, self.image_topic, self.on_raw_image, freshest_frame
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
                message.height, message.step // 2
            )[:, :message.width]
            if message.is_bigendian:
                depth = depth.byteswap()
        elif message.encoding == METER_DEPTH_ENCODING:
            depth = np.frombuffer(message.data, np.float32).reshape(
                message.height, message.step // 4
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

    def claim_detection_slot(self):
        if not self.is_enabled:
            return False
        now = self.get_clock().now()
        if (self.previous_detection_time is not None
                and now - self.previous_detection_time < self.min_detection_interval):
            return False
        self.previous_detection_time = now
        return True

    def on_compressed_image(self, message):
        if not self.claim_detection_slot():
            return
        rgb = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR_RGB)
        if rgb is None:
            return
        self.detect(rgb, message.header.stamp)

    def on_raw_image(self, message):
        if not self.claim_detection_slot():
            return
        bgr = np.frombuffer(message.data, np.uint8).reshape(
            message.height, message.width, 3)
        self.detect(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB), message.header.stamp)

    def detect(self, rgb, stamp):
        height, width = rgb.shape[:2]
        boxes, classes, scores, count = self.session.run(
            None, {self.input_name: rgb[np.newaxis]})

        detections = Detection2DArray()
        detections.header.stamp = stamp
        detections.header.frame_id = self.depth_frame_id
        overlay = ImageAnnotations()
        for index in range(int(count[0])):
            if int(classes[0, index]) != self.person_class_id:
                continue
            score = float(scores[0, index])
            if score < self.min_score:
                continue
            top, left, bottom, right = boxes[0, index]
            bounding_box = (
                left * width, top * height,
                (right - left) * width, (bottom - top) * height,
            )
            distance, point = self.bounding_box_range(bounding_box, width, height)
            detections.detections.append(
                self.detection(stamp, bounding_box, score, point))
            self.annotate(overlay, stamp, bounding_box, distance)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

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

    def detection(self, stamp, bounding_box, score, point):
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
        hypothesis.hypothesis.score = score
        if point is not None:
            hypothesis.pose.pose.position = point
        detection.results.append(hypothesis)
        return detection

    def annotate(self, overlay, stamp, bounding_box, distance):
        x, y, w, h = bounding_box
        box = PointsAnnotation()
        box.timestamp = stamp
        box.type = PointsAnnotation.LINE_LOOP
        box.points = [
            Point2(x=float(x), y=float(y)),
            Point2(x=float(x + w), y=float(y)),
            Point2(x=float(x + w), y=float(y + h)),
            Point2(x=float(x), y=float(y + h)),
        ]
        box.outline_color = PERSON_COLOR
        box.thickness = 2.0
        overlay.points.append(box)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(
            x=float(x), y=max(float(y) - LABEL_MARGIN_PIXELS, 0.0))
        distance_text = f'{distance:.1f}m' if distance is not None else '?'
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
