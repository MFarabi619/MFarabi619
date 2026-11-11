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

from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)
from zed_msgs.msg import ObjectsStamped

OBJECT_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

LABEL_MARGIN_PIXELS = 6.0
BOX_THICKNESS = 2.0
LABEL_FONT_SIZE = 18.0
TRACKING_STATE_OK = 1
TRACKING_STATE_SEARCHING = 2
CONFIDENCE_FULL_SCALE = 100.0


class ZedObjectOverlay(Node):
    def __init__(self):
        super().__init__('zed_object_overlay')
        self.declare_parameter('objects_topic', '/sensors/camera_0/objects')
        self.declare_parameter('detections_topic', 'detections')
        self.declare_parameter('overlay_topic', 'perception/vision/overlay')
        self.detections_publisher = self.create_publisher(
            Detection2DArray,
            self.get_parameter('detections_topic').value,
            qos_profile_sensor_data)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations,
            self.get_parameter('overlay_topic').value,
            qos_profile_sensor_data)
        objects_topic = self.get_parameter('objects_topic').value
        self.create_subscription(
            ObjectsStamped, objects_topic, self.on_objects,
            qos_profile_sensor_data)
        self.get_logger().info(f'zed object overlay: {objects_topic}')

    def on_objects(self, message):
        detections = Detection2DArray()
        detections.header = message.header
        overlay = ImageAnnotations()
        for tracked_object in message.objects:
            if tracked_object.tracking_available \
                    and tracked_object.tracking_state not in (
                        TRACKING_STATE_OK, TRACKING_STATE_SEARCHING):
                continue
            corners = tracked_object.bounding_box_2d.corners
            left = float(corners[0].kp[0])
            top = float(corners[0].kp[1])
            right = float(corners[2].kp[0])
            bottom = float(corners[2].kp[1])
            if right <= left or bottom <= top:
                continue
            detections.detections.append(self.detection(
                message.header, tracked_object, left, top, right, bottom))
            self.annotate(
                overlay, message.header.stamp, tracked_object,
                left, top, right, bottom)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def detection(self, header, tracked_object, left, top, right, bottom):
        detection = Detection2D()
        detection.header = header
        detection.id = str(tracked_object.label_id)
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(
                x=(left + right) / 2.0, y=(top + bottom) / 2.0)),
            size_x=right - left,
            size_y=bottom - top)
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = tracked_object.label.lower()
        hypothesis.hypothesis.score = (
            tracked_object.confidence / CONFIDENCE_FULL_SCALE)
        detection.results.append(hypothesis)
        return detection

    def annotate(
            self, overlay, stamp, tracked_object, left, top, right, bottom):
        box = PointsAnnotation()
        box.timestamp = stamp
        box.type = PointsAnnotation.LINE_LOOP
        box.points = [
            Point2(x=left, y=top),
            Point2(x=right, y=top),
            Point2(x=right, y=bottom),
            Point2(x=left, y=bottom),
        ]
        box.outline_color = OBJECT_COLOR
        box.thickness = BOX_THICKNESS
        overlay.points.append(box)
        label = TextAnnotation()
        label.timestamp = stamp
        label.position = Point2(
            x=left, y=max(top - LABEL_MARGIN_PIXELS, 0.0))
        distance = math.hypot(*tracked_object.position)
        label.text = f'{tracked_object.label.lower()} {distance:.1f}m'
        label.font_size = LABEL_FONT_SIZE
        label.text_color = TEXT_COLOR
        label.background_color = TEXT_BACKGROUND_COLOR
        overlay.texts.append(label)


def main():
    rclpy.init()
    node = ZedObjectOverlay()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
