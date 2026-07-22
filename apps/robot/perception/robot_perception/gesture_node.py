import os

import cv2
import mediapipe as mp
import numpy as np
import rclpy
from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.components.processors.classifier_options import (
    ClassifierOptions,
)
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose

DEFAULT_MODEL = os.path.join(os.path.dirname(__file__), "models", "gesture_recognizer.task")

GREEN = Color(r=0.2, g=1.0, b=0.4, a=1.0)
WHITE = Color(r=1.0, g=1.0, b=1.0, a=1.0)
SHADE = Color(r=0.0, g=0.0, b=0.0, a=0.6)
BONE = Color(r=0.9, g=0.9, b=0.9, a=0.9)
JOINT = Color(r=1.0, g=0.6, b=0.1, a=1.0)


class GestureRecognizer(Node):
    def __init__(self):
        super().__init__("gesture_recognizer")
        self.image_topic = self.declare_parameter(
            "image_topic", "sensors/camera_0/color/image_raw/compressed"
        ).value
        detections_topic = self.declare_parameter(
            "detections_topic", "perception/gestures"
        ).value
        overlay_topic = self.declare_parameter(
            "overlay_topic", "perception/gestures/overlay"
        ).value
        model = self.declare_parameter("model", DEFAULT_MODEL).value
        hands = self.declare_parameter("num_hands", 1).value

        options = vision.GestureRecognizerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=model),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=hands,
            min_tracking_confidence=0.5,
            canned_gesture_classifier_options=ClassifierOptions(
                score_threshold=0.6, category_denylist=["None"]
            ),
        )
        self.recognizer = vision.GestureRecognizer.create_from_options(options)
        self.last_timestamp_ms = 0

        self.publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, qos_profile_sensor_data
        )
        self.get_logger().info(
            f"gesture recognizer: {self.image_topic} -> {detections_topic} (+ {overlay_topic})"
        )

    def on_image(self, message):
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

        detections = Detection2DArray()
        detections.header = message.header
        overlay = ImageAnnotations()
        height, width = rgb.shape[:2]
        for gestures, landmarks in zip(result.gestures, result.hand_landmarks):
            if not gestures:
                continue
            top = gestures[0]
            xs = [landmark.x for landmark in landmarks]
            ys = [landmark.y for landmark in landmarks]
            x0, x1 = min(xs) * width, max(xs) * width
            y0, y1 = min(ys) * height, max(ys) * height

            detection = Detection2D()
            detection.header = message.header
            hypothesis = ObjectHypothesisWithPose()
            hypothesis.hypothesis.class_id = top.category_name
            hypothesis.hypothesis.score = float(top.score)
            detection.results.append(hypothesis)
            detection.bbox.center.position.x = (x0 + x1) / 2.0
            detection.bbox.center.position.y = (y0 + y1) / 2.0
            detection.bbox.size_x = x1 - x0
            detection.bbox.size_y = y1 - y0
            detections.detections.append(detection)

            overlay.points.append(self.box(message.header.stamp, x0, y0, x1, y1))
            overlay.points.append(self.bones(message.header.stamp, landmarks, width, height))
            overlay.points.append(self.joints(message.header.stamp, landmarks, width, height))
            overlay.texts.append(self.label(message.header.stamp, x0, y0, top))

        self.publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def box(self, stamp, x0, y0, x1, y1):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LOOP
        annotation.points = [
            Point2(x=x0, y=y0),
            Point2(x=x1, y=y0),
            Point2(x=x1, y=y1),
            Point2(x=x0, y=y1),
        ]
        annotation.outline_color = GREEN
        annotation.thickness = 2.0
        return annotation

    def bones(self, stamp, landmarks, width, height):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LIST
        points = []
        for connection in vision.HandLandmarksConnections.HAND_CONNECTIONS:
            for index in (connection.start, connection.end):
                points.append(Point2(x=landmarks[index].x * width, y=landmarks[index].y * height))
        annotation.points = points
        annotation.outline_color = BONE
        annotation.thickness = 2.0
        return annotation

    def joints(self, stamp, landmarks, width, height):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.POINTS
        annotation.points = [Point2(x=lm.x * width, y=lm.y * height) for lm in landmarks]
        annotation.outline_color = JOINT
        annotation.thickness = 5.0
        return annotation

    def label(self, stamp, x0, y0, gesture):
        annotation = TextAnnotation()
        annotation.timestamp = stamp
        annotation.position = Point2(x=x0, y=max(y0 - 6.0, 0.0))
        annotation.text = f"{gesture.category_name} {gesture.score:.2f}"
        annotation.font_size = 18.0
        annotation.text_color = WHITE
        annotation.background_color = SHADE
        return annotation


def main():
    rclpy.init()
    node = GestureRecognizer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
