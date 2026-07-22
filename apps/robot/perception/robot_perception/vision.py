import cv2
import numpy as np
import rclpy
from foxglove_msgs.msg import (
    Color,
    ImageAnnotations,
    Point2,
    PointsAnnotation,
    TextAnnotation,
)
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage

CROP = Color(r=0.2, g=1.0, b=0.4, a=1.0)
CENTER = Color(r=1.0, g=0.6, b=0.1, a=1.0)
WHITE = Color(r=1.0, g=1.0, b=1.0, a=1.0)
SHADE = Color(r=0.0, g=0.0, b=0.0, a=0.6)


class Vision(Node):
    def __init__(self):
        super().__init__("vision")
        self.image_topic = self.declare_parameter(
            "image_topic", "sensors/camera_0/color/image/compressed"
        ).value
        overlay_topic = self.declare_parameter(
            "overlay_topic", "perception/vision/overlay"
        ).value
        self.roi_top = self.declare_parameter("roi_top", 0.5).value
        self.roi_bottom = self.declare_parameter("roi_bottom", 1.0).value
        self.green_hue_min = self.declare_parameter("green_hue_min", 70.0).value
        self.green_hue_max = self.declare_parameter("green_hue_max", 175.0).value
        self.min_saturation = self.declare_parameter("min_saturation", 0.30).value
        self.min_value = self.declare_parameter("min_value", 0.06).value
        self.crop_min_fraction = self.declare_parameter("crop_min_fraction", 0.40).value
        self.min_row_width = self.declare_parameter("min_row_width", 0.04).value
        self.smooth_window = self.declare_parameter("smooth_window", 9).value

        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data
        )
        self.create_subscription(
            CompressedImage, self.image_topic, self.on_image, qos_profile_sensor_data
        )
        self.get_logger().info(f"vision: {self.image_topic} -> {overlay_topic}")

    def on_image(self, message):
        bgr = cv2.imdecode(np.frombuffer(message.data, np.uint8), cv2.IMREAD_COLOR)
        if bgr is None:
            return
        height, width = bgr.shape[:2]
        top = int(height * self.roi_top)
        bottom = int(height * self.roi_bottom)

        hsv = cv2.cvtColor(bgr[top:bottom], cv2.COLOR_BGR2HSV)
        crop_mask = cv2.inRange(
            hsv,
            (self.green_hue_min / 2.0, self.min_saturation * 255.0, self.min_value * 255.0),
            (self.green_hue_max / 2.0, 255.0, 255.0),
        )
        fraction = crop_mask.mean(axis=0) / 255.0
        kernel = np.ones(self.smooth_window) / self.smooth_window
        smoothed = np.convolve(fraction, kernel, mode="same")

        runs = self.contiguous_runs(smoothed >= self.crop_min_fraction)
        runs = [(a, b) for a, b in runs if (b - a) >= self.min_row_width * width]
        center_run = min(
            runs, key=lambda run: abs((run[0] + run[1]) / 2.0 - width / 2.0), default=None
        )

        overlay = ImageAnnotations()
        for run in runs:
            overlay.points.append(
                self.run_box(message.header.stamp, run, top, bottom, run == center_run)
            )
        if center_run is not None:
            offset = ((center_run[0] + center_run[1]) / 2.0 - width / 2.0) / (width / 2.0)
            overlay.texts.append(self.offset_label(message.header.stamp, center_run, top, offset))
        self.overlay_publisher.publish(overlay)

    def contiguous_runs(self, above):
        edges = np.flatnonzero(np.diff(above.astype(np.int8)))
        bounds = np.concatenate(([0], edges + 1, [above.size]))
        return [
            (int(bounds[i]), int(bounds[i + 1]))
            for i in range(len(bounds) - 1)
            if above[bounds[i]]
        ]

    def run_box(self, stamp, run, top, bottom, is_center):
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
        annotation.outline_color = CENTER if is_center else CROP
        annotation.thickness = 3.0 if is_center else 2.0
        return annotation

    def offset_label(self, stamp, run, top, offset):
        annotation = TextAnnotation()
        annotation.timestamp = stamp
        annotation.position = Point2(x=float(run[0]), y=max(float(top) - 6.0, 0.0))
        annotation.text = f"row offset {offset:+.2f}"
        annotation.font_size = 18.0
        annotation.text_color = WHITE
        annotation.background_color = SHADE
        return annotation


def main():
    rclpy.init()
    node = Vision()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
