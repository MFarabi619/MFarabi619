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


from foxglove_msgs.msg import (
    CircleAnnotation,
    Color,
    ImageAnnotations,
    Point2,
    TextAnnotation,
)
from geometry_msgs.msg import Point
from image_geometry import PinholeCameraModel
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo
from tf2_ros import Buffer, TransformListener
from tf2_ros import LookupException, ConnectivityException, ExtrapolationException
from vision_msgs.msg import (
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
)

OPERATOR_LABEL = 'operator'
OPERATOR_COLOR = Color(r=0.1, g=0.9, b=1.0, a=1.0)
OPERATOR_FILL_COLOR = Color(r=0.1, g=0.9, b=1.0, a=0.25)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)
OPERATOR_DIAMETER_PIXELS = 26.0
LABEL_MARGIN_PIXELS = 8.0
LIVE_PARAMETERS = frozenset({'transform_timeout'})


class AprilTagOperatorAdapter(Node):
    def __init__(self):
        super().__init__('apriltag_operator_adapter')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/operator/overlay').value
        self.camera_info_topic = self.declare_parameter(
            'camera_info_topic', '/sensors/camera_0/color/camera_info').value
        self.camera_frame = self.declare_parameter(
            'camera_frame', 'camera_0_color_optical_frame').value
        self.tag_frame = self.declare_parameter('tag_frame', OPERATOR_LABEL).value
        self.publish_rate_hz = self.declare_parameter('publish_rate_hz', 20.0).value
        self.transform_timeout = self.declare_parameter('transform_timeout', 0.4).value

        self.camera_model = None

        self.buffer = Buffer()
        self.listener = TransformListener(self.buffer, self)
        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(
            CameraInfo, self.camera_info_topic, self.on_camera_info,
            qos_profile_sensor_data)
        self.create_timer(1.0 / self.publish_rate_hz, self.publish_detection)
        self.get_logger().info(
            f'apriltag operator: tf {self.camera_frame} -> {self.tag_frame}')

    def on_camera_info(self, message):
        if self.camera_model is None:
            self.camera_model = PinholeCameraModel()
        self.camera_model.from_camera_info(message)

    def publish_detection(self):
        detections = Detection2DArray()
        detections.header.frame_id = self.camera_frame
        detections.header.stamp = self.get_clock().now().to_msg()
        overlay = ImageAnnotations()
        translation = self.latest_translation()
        if translation is not None:
            detections.detections.append(self.detection(translation))
            self.annotate(overlay, translation)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def latest_translation(self):
        try:
            transform = self.buffer.lookup_transform(
                self.camera_frame, self.tag_frame, rclpy.time.Time())
        except (LookupException, ConnectivityException, ExtrapolationException):
            return None
        age = self.get_clock().now() - rclpy.time.Time.from_msg(
            transform.header.stamp)
        if age > Duration(seconds=self.transform_timeout):
            return None
        return transform.transform.translation

    def detection(self, translation):
        detection = Detection2D()
        detection.header.frame_id = self.camera_frame
        detection.header.stamp = self.get_clock().now().to_msg()
        detection.id = OPERATOR_LABEL
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = OPERATOR_LABEL
        hypothesis.hypothesis.score = 1.0
        hypothesis.pose.pose.position = Point(
            x=translation.x, y=translation.y, z=translation.z)
        detection.results.append(hypothesis)
        return detection

    def annotate(self, overlay, translation):
        if self.camera_model is None or translation.z <= 0.0:
            return
        stamp = self.get_clock().now().to_msg()
        column, row = self.camera_model.project_3d_to_pixel(
            (translation.x, translation.y, translation.z))
        marker = CircleAnnotation()
        marker.timestamp = stamp
        marker.position = Point2(x=column, y=row)
        marker.diameter = OPERATOR_DIAMETER_PIXELS
        marker.thickness = 2.5
        marker.outline_color = OPERATOR_COLOR
        marker.fill_color = OPERATOR_FILL_COLOR
        overlay.circles.append(marker)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(
            x=column, y=max(row - OPERATOR_DIAMETER_PIXELS / 2.0 - LABEL_MARGIN_PIXELS, 0.0))
        label.text = f'{OPERATOR_LABEL} {translation.z:.2f} m'
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
    node = AprilTagOperatorAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
