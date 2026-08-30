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
from mediapipe.tasks.python.components.processors.classifier_options import (
    ClassifierOptions,
)
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose

MODEL_FILENAME = 'gesture_recognizer.task'


def default_model_path():
    directory = os.path.dirname(__file__)
    alongside = os.path.join(directory, 'models', MODEL_FILENAME)
    if os.path.exists(alongside):
        return alongside
    return os.path.normpath(
        os.path.join(directory, '..', 'models', MODEL_FILENAME))


DEFAULT_MODEL_PATH = default_model_path()

FORWARD_COLOR = Color(r=0.722, g=0.733, b=0.149, a=1.0)
REVERSE_COLOR = Color(r=0.996, g=0.502, b=0.098, a=1.0)
TURN_COLOR = Color(r=0.980, g=0.741, b=0.184, a=1.0)
STOP_COLOR = Color(r=0.984, g=0.286, b=0.204, a=1.0)
LANDMARK_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.65)

MOTION_EPSILON = 0.02
LABEL_MARGIN_PIXELS = 8.0
LABEL_FONT_SIZE = 18.0


def with_alpha(color, alpha):
    return Color(r=color.r, g=color.g, b=color.b, a=alpha)


class HandGestureDetector(Node):
    def __init__(self):
        super().__init__('hand_gesture_detector')
        self.image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed'
        ).value
        detections_topic = self.declare_parameter(
            'detections_topic', 'perception/gestures'
        ).value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/gestures/overlay'
        ).value
        model_path = self.declare_parameter('model', DEFAULT_MODEL_PATH).value
        num_hands = self.declare_parameter('num_hands', 1).value
        min_hand_detection_confidence = self.declare_parameter(
            'min_hand_detection_confidence', 0.5).value

        options = vision.GestureRecognizerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=model_path),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=num_hands,
            min_hand_detection_confidence=min_hand_detection_confidence,
            min_tracking_confidence=0.5,
            canned_gesture_classifier_options=ClassifierOptions(
                score_threshold=0.6, category_denylist=['None']
            ),
        )
        self.recognizer = vision.GestureRecognizer.create_from_options(options)
        self.last_timestamp_ms = 0
        self.forward_speed = 0.0
        self.turn_speed = 0.0

        self.is_enabled = self.declare_parameter('start_enabled', False).value
        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data
        )
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, qos_profile_sensor_data
        )
        self.create_subscription(
            TwistStamped, '/joy_teleop/cmd_vel', self.on_cmd_vel,
            qos_profile_sensor_data
        )
        self.get_logger().info(
            f'hand gesture detector: {self.image_topic} -> {detections_topic} (+ {overlay_topic})'
        )

    def on_cmd_vel(self, message):
        self.forward_speed = message.twist.linear.x
        self.turn_speed = message.twist.angular.z

    def motion_style(self):
        if abs(self.forward_speed) > MOTION_EPSILON:
            if self.forward_speed > 0.0:
                return FORWARD_COLOR, f'▲ FORWARD  {self.forward_speed:.1f} m/s'
            return REVERSE_COLOR, f'▼ REVERSE  {abs(self.forward_speed):.1f} m/s'
        if abs(self.turn_speed) > MOTION_EPSILON:
            if self.turn_speed > 0.0:
                return TURN_COLOR, f'◀ LEFT  {self.turn_speed:.1f} rad/s'
            return TURN_COLOR, f'▶ RIGHT  {abs(self.turn_speed):.1f} rad/s'
        return STOP_COLOR, '■ STOP'

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_image(self, message):
        if not self.is_enabled:
            return
        rgb = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR_RGB)
        if rgb is None:
            return
        stamp = message.header.stamp
        timestamp_ms = max(
            self.last_timestamp_ms + 1, stamp.sec * 1000 + stamp.nanosec // 1_000_000
        )
        self.last_timestamp_ms = timestamp_ms
        result = self.recognizer.recognize_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp_ms
        )

        color, motion_label = self.motion_style()
        detections = Detection2DArray()
        detections.header = message.header
        overlay = ImageAnnotations()
        height, width = rgb.shape[:2]
        for gestures, landmarks, handedness in zip(
                result.gestures, result.hand_landmarks, result.handedness):
            if gestures:
                top_gesture = gestures[0]
                class_id = top_gesture.category_name
                score = float(top_gesture.score)
            elif handedness:
                class_id = 'Hand'
                score = float(handedness[0].score)
            else:
                continue
            xs = [landmark.x for landmark in landmarks]
            ys = [landmark.y for landmark in landmarks]
            x0, x1 = min(xs) * width, max(xs) * width
            y0, y1 = min(ys) * height, max(ys) * height

            detection = Detection2D()
            detection.header = message.header
            hypothesis = ObjectHypothesisWithPose()
            hypothesis.hypothesis.class_id = class_id
            hypothesis.hypothesis.score = score
            detection.results.append(hypothesis)
            detection.bbox.center.position.x = (x0 + x1) / 2.0
            detection.bbox.center.position.y = (y0 + y1) / 2.0
            detection.bbox.size_x = x1 - x0
            detection.bbox.size_y = y1 - y0
            detections.detections.append(detection)

            label_text = f'{class_id} {score:.0%}   {motion_label}'
            overlay.points.append(self.box(stamp, x0, y0, x1, y1, color))
            overlay.points.append(
                self.connections(stamp, landmarks, width, height, color))
            overlay.points.append(
                self.landmark_points(stamp, landmarks, width, height))
            overlay.texts.append(self.label(stamp, x0, y0, label_text, color))

        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def box(self, stamp, x0, y0, x1, y1, color):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LOOP
        annotation.points = [
            Point2(x=x0, y=y0),
            Point2(x=x1, y=y0),
            Point2(x=x1, y=y1),
            Point2(x=x0, y=y1),
        ]
        annotation.outline_color = color
        annotation.thickness = 3.0
        return annotation

    def connections(self, stamp, landmarks, width, height, color):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LIST
        points = []
        for connection in vision.HandLandmarksConnections.HAND_CONNECTIONS:
            for index in (connection.start, connection.end):
                points.append(Point2(x=landmarks[index].x * width, y=landmarks[index].y * height))
        annotation.points = points
        annotation.outline_color = with_alpha(color, 0.85)
        annotation.thickness = 2.0
        return annotation

    def landmark_points(self, stamp, landmarks, width, height):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.POINTS
        annotation.points = [
            Point2(x=landmark.x * width, y=landmark.y * height)
            for landmark in landmarks
        ]
        annotation.outline_color = LANDMARK_COLOR
        annotation.thickness = 5.0
        return annotation

    def label(self, stamp, x0, y0, text, color):
        annotation = TextAnnotation()
        annotation.timestamp = stamp
        annotation.position = Point2(x=x0, y=max(y0 - LABEL_MARGIN_PIXELS, 0.0))
        annotation.text = text
        annotation.font_size = LABEL_FONT_SIZE
        annotation.text_color = color
        annotation.background_color = TEXT_BACKGROUND_COLOR
        return annotation


def main():
    rclpy.init()
    node = HandGestureDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
