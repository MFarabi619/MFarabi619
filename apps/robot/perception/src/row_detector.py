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
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)

ROW_COLOR = Color(r=0.2, g=1.0, b=0.4, a=1.0)
CENTER_ROW_COLOR = Color(r=1.0, g=0.6, b=0.1, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

LABEL_MARGIN_PIXELS = 6.0


class RowDetector(Node):
    def __init__(self):
        super().__init__('row_detector')
        self.image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image/compressed'
        ).value
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/vision/overlay'
        ).value
        self.class_label = self.declare_parameter('class_label', 'crop_row').value
        self.roi_top = self.declare_parameter('roi_top', 0.5).value
        self.roi_bottom = self.declare_parameter('roi_bottom', 1.0).value
        self.hue_min = self.declare_parameter('hue_min', 35.0).value
        self.hue_max = self.declare_parameter('hue_max', 87.0).value
        self.min_saturation = self.declare_parameter('min_saturation', 0.30).value
        self.min_value = self.declare_parameter('min_value', 0.06).value
        self.min_fraction = self.declare_parameter('min_fraction', 0.40).value
        self.min_row_width = self.declare_parameter('min_row_width', 0.04).value
        self.smooth_window = self.declare_parameter('smooth_window', 9).value

        self.detections_publisher = self.create_publisher(
            Detection2DArray, detections_topic, qos_profile_sensor_data
        )
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, qos_profile_sensor_data
        )
        self.get_logger().info(f'row detector {self.class_label}: {self.image_topic}')

    def on_image(self, message):
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        height, width = bgr.shape[:2]
        top = int(height * self.roi_top)
        bottom = int(height * self.roi_bottom)

        fraction = self.row_fraction(bgr[top:bottom])
        runs = [
            (start, end)
            for start, end in self.contiguous_runs(fraction >= self.min_fraction)
            if (end - start) >= self.min_row_width * width
        ]
        center_run = min(
            runs, key=lambda run: abs((run[0] + run[1]) / 2.0 - width / 2.0), default=None
        )

        detections = Detection2DArray()
        detections.header.stamp = message.header.stamp
        detections.header.frame_id = message.header.frame_id
        overlay = ImageAnnotations()
        for run in runs:
            detections.detections.append(
                self.detection(message.header.stamp, run, fraction, top, bottom))
            overlay.points.append(
                self.run_box(message.header.stamp, run, top, bottom, center_run))
        if center_run is not None:
            offset = ((center_run[0] + center_run[1]) / 2.0 - width / 2.0) / (width / 2.0)
            overlay.texts.append(self.offset_label(message.header.stamp, center_run, top, offset))
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)

    def row_fraction(self, roi_band):
        hsv = cv2.cvtColor(roi_band, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(
            hsv,
            (self.hue_min, self.min_saturation * 255.0, self.min_value * 255.0),
            (self.hue_max, 255.0, 255.0),
        )
        column_fraction = mask.mean(axis=0) / 255.0
        kernel = np.ones(self.smooth_window) / self.smooth_window
        return np.convolve(column_fraction, kernel, mode='same')

    def contiguous_runs(self, is_above_threshold):
        edges = np.flatnonzero(np.diff(is_above_threshold.astype(np.int8)))
        bounds = np.concatenate(([0], edges + 1, [is_above_threshold.size]))
        return [
            (int(bounds[i]), int(bounds[i + 1]))
            for i in range(len(bounds) - 1)
            if is_above_threshold[bounds[i]]
        ]

    def detection(self, stamp, run, fraction, top, bottom):
        start, end = run
        detection = Detection2D()
        detection.header.stamp = stamp
        detection.id = self.class_label
        detection.bbox = BoundingBox2D(
            center=Pose2D(
                position=Point2D(x=(start + end) / 2.0, y=(top + bottom) / 2.0), theta=0.0),
            size_x=float(end - start),
            size_y=float(bottom - top),
        )
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = self.class_label
        hypothesis.hypothesis.score = float(fraction[start:end].mean())
        detection.results.append(hypothesis)
        return detection

    def run_box(self, stamp, run, top, bottom, center_run):
        annotation = PointsAnnotation()
        annotation.timestamp = stamp
        annotation.type = PointsAnnotation.LINE_LOOP
        x0, x1 = float(run[0]), float(run[1])
        annotation.points = [
            Point2(x=x0, y=float(top)),
            Point2(x=x1, y=float(top)),
            Point2(x=x1, y=float(bottom - 1)),
            Point2(x=x0, y=float(bottom - 1)),
        ]
        is_center = run == center_run
        annotation.outline_color = CENTER_ROW_COLOR if is_center else ROW_COLOR
        annotation.thickness = 3.0 if is_center else 2.0
        return annotation

    def offset_label(self, stamp, run, top, offset):
        annotation = TextAnnotation()
        annotation.timestamp = stamp
        annotation.position = Point2(
            x=float(run[0]), y=max(float(top) - LABEL_MARGIN_PIXELS, 0.0))
        annotation.text = f'{self.class_label} offset {offset:+.2f}'
        annotation.font_size = 18.0
        annotation.text_color = TEXT_COLOR
        annotation.background_color = TEXT_BACKGROUND_COLOR
        return annotation


def main():
    rclpy.init()
    node = RowDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
