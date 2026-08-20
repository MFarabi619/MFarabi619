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
import onnxruntime
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

SIDEWALK_COLOR = Color(r=0.2, g=0.6, b=1.0, a=1.0)
CENTER_COLOR = Color(r=1.0, g=0.6, b=0.1, a=1.0)
TEXT_COLOR = Color(r=1.0, g=1.0, b=1.0, a=1.0)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)

LABEL_MARGIN_PIXELS = 6.0

IMAGENET_MEAN_RGB = (123.675, 116.28, 103.53, 0.0)
IMAGENET_RECIPROCAL_STD_RGB = (1.0 / 58.395, 1.0 / 57.12, 1.0 / 57.375, 0.0)


class SidewalkDetector(Node):
    def __init__(self):
        super().__init__('sidewalk_detector')
        self.image_topic = self.declare_parameter(
            'image_topic', 'sensors/camera_0/color/image_raw/compressed'
        ).value
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/vision/overlay'
        ).value
        model_path = self.declare_parameter(
            'model_path', 'perception/models/sidewalk-segformer-b0.onnx'
        ).value
        self.class_label = self.declare_parameter('class_label', 'sidewalk').value
        self.sidewalk_class_ids = self.declare_parameter(
            'sidewalk_class_ids', [2, 3]
        ).value
        self.input_size = self.declare_parameter('input_size', 512).value
        self.roi_top_fraction = self.declare_parameter('roi_top_fraction', 0.4).value
        self.roi_bottom = self.declare_parameter('roi_bottom', 1.0).value
        self.min_fraction = self.declare_parameter('min_fraction', 0.5).value
        self.min_run_width = self.declare_parameter('min_run_width', 0.10).value
        self.smooth_window = self.declare_parameter('smooth_window', 9).value

        self.session = onnxruntime.InferenceSession(
            model_path, providers=['CPUExecutionProvider'])
        self.input_name = self.session.get_inputs()[0].name
        self.blob_params = cv2.dnn.Image2BlobParams()
        self.blob_params.size = (self.input_size, self.input_size)
        self.blob_params.swapRB = True
        self.blob_params.mean = IMAGENET_MEAN_RGB
        self.blob_params.scalefactor = IMAGENET_RECIPROCAL_STD_RGB
        self.blob_params.ddepth = cv2.CV_32F

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
            f'sidewalk detector {model_path}: {self.image_topic}')

    def on_image(self, message):
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        height, width = bgr.shape[:2]
        top = int(height * self.roi_top_fraction)
        bottom = int(height * self.roi_bottom)

        mask = self.sidewalk_mask(bgr)
        fraction = self.column_fraction(mask[top:bottom])
        above_threshold = fraction >= self.min_fraction
        runs = [
            (int(run.start), int(run.stop))
            for run in np.ma.clump_masked(np.ma.masked_array(above_threshold, above_threshold))
            if (run.stop - run.start) >= self.min_run_width * width
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

    def sidewalk_mask(self, bgr):
        height, width = bgr.shape[:2]
        batch = cv2.dnn.blobFromImageWithParams(bgr, self.blob_params)
        logits = self.session.run(None, {self.input_name: batch})[0]
        classes = logits[0].argmax(axis=0).astype(np.uint8)
        mask = np.isin(classes, self.sidewalk_class_ids).astype(np.uint8)
        return cv2.resize(mask, (width, height), interpolation=cv2.INTER_NEAREST)

    def column_fraction(self, mask_band):
        column_fraction = mask_band.mean(axis=0)
        kernel = np.ones(self.smooth_window) / self.smooth_window
        return np.convolve(column_fraction, kernel, mode='same')

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
        annotation.outline_color = CENTER_COLOR if is_center else SIDEWALK_COLOR
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
    node = SidewalkDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
