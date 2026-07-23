import os

import mediapipe as mp
import rclpy
from cv_bridge import CvBridge, CvBridgeError
from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
import requests
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.components.processors.classifier_options import (
    ClassifierOptions,
)
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose

DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(__file__), "models", "gesture_recognizer.task")
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
    "gesture_recognizer/float16/1/gesture_recognizer.task"
)

BOX_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)
BONE_COLOR = Color(r=0.9, g=0.9, b=0.9, a=0.9)
JOINT_COLOR = Color(r=1.0, g=0.6, b=0.1, a=1.0)

LABEL_OFFSET_PIXELS = 6.0


def download_model(path):
    response = requests.get(MODEL_URL)
    response.raise_for_status()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as file:
        file.write(response.content)


class HandGestureRecognizer(Node):
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
        model_path = self.declare_parameter("model", DEFAULT_MODEL_PATH).value
        num_hands = self.declare_parameter("num_hands", 1).value

        if not os.path.isfile(model_path):
            self.get_logger().info(f"{model_path} not found, downloading...")
            download_model(model_path)

        options = vision.GestureRecognizerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=model_path),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=num_hands,
            min_tracking_confidence=0.5,
            canned_gesture_classifier_options=ClassifierOptions(
                score_threshold=0.6, category_denylist=["None"]
            ),
        )
        self.recognizer = vision.GestureRecognizer.create_from_options(options)
        self.cv_bridge = CvBridge()
        self.last_timestamp_ms = 0

        self.detections_publisher = self.create_publisher(
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
        try:
            rgb = self.cv_bridge.compressed_imgmsg_to_cv2(message, desired_encoding="rgb8")
        except CvBridgeError:
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
            top_gesture = gestures[0]
            xs = [landmark.x for landmark in landmarks]
            ys = [landmark.y for landmark in landmarks]
            x0, x1 = min(xs) * width, max(xs) * width
            y0, y1 = min(ys) * height, max(ys) * height

            detection = Detection2D()
            detection.header = message.header
            hypothesis = ObjectHypothesisWithPose()
            hypothesis.hypothesis.class_id = top_gesture.category_name
            hypothesis.hypothesis.score = float(top_gesture.score)
            detection.results.append(hypothesis)
            detection.bbox.center.position.x = (x0 + x1) / 2.0
            detection.bbox.center.position.y = (y0 + y1) / 2.0
            detection.bbox.size_x = x1 - x0
            detection.bbox.size_y = y1 - y0
            detections.detections.append(detection)

            overlay.points.append(self.box(message.header.stamp, x0, y0, x1, y1))
            overlay.points.append(self.bones(message.header.stamp, landmarks, width, height))
            overlay.points.append(self.joints(message.header.stamp, landmarks, width, height))
            overlay.texts.append(self.label(message.header.stamp, x0, y0, top_gesture))

        self.detections_publisher.publish(detections)
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
        annotation.outline_color = BOX_COLOR
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
        annotation.outline_color = BONE_COLOR
        annotation.thickness = 2.0
        return annotation

    def joints(self, stamp, landmarks, width, height):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.POINTS
        annotation.points = [
            Point2(x=landmark.x * width, y=landmark.y * height)
            for landmark in landmarks
        ]
        annotation.outline_color = JOINT_COLOR
        annotation.thickness = 5.0
        return annotation

    def label(self, stamp, x0, y0, gesture):
        annotation = TextAnnotation()
        annotation.timestamp = stamp
        annotation.position = Point2(x=x0, y=max(y0 - LABEL_OFFSET_PIXELS, 0.0))
        annotation.text = f"{gesture.category_name} {gesture.score:.2f}"
        annotation.font_size = 18.0
        annotation.text_color = TEXT_COLOR
        annotation.background_color = TEXT_BACKGROUND_COLOR
        return annotation


def main():
    rclpy.init()
    node = HandGestureRecognizer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
