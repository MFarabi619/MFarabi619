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
from image_geometry import PinholeCameraModel
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, PointCloud2
from sensor_msgs_py.point_cloud2 import read_points_numpy
from tf2_ros import Buffer, TransformListener
from tf2_sensor_msgs import transform_points

STOP_COLOR = Color(r=1.0, g=0.25, b=0.2, a=0.85)
SLOWDOWN_COLOR = Color(r=1.0, g=0.7, b=0.1, a=0.6)
TEXT_BACKGROUND_COLOR = Color(r=0.0, g=0.0, b=0.0, a=0.6)
POINT_DIAMETER_PX = 5.0
POINT_THICKNESS_PX = 1.0
MAX_POINTS_PER_ZONE = 200
LABEL_MARGIN_PX = 10.0
LABEL_FONT_SIZE = 18.0


class CollisionOverlay(Node):
    def __init__(self):
        super().__init__('collision_overlay')
        cloud_topic = self.declare_parameter(
            'cloud_topic', 'sensors/camera_0/depth/points').value
        camera_info_topic = self.declare_parameter(
            'camera_info_topic', 'sensors/camera_0/color/camera_info').value
        overlay_topic = self.declare_parameter(
            'overlay_topic', 'perception/collision/overlay').value
        self.base_frame = self.declare_parameter('base_frame', 'base_link').value
        self.min_height = self.declare_parameter('min_height', 0.15).value
        self.max_height = self.declare_parameter('max_height', 2.0).value
        self.stop_x_range = self.declare_parameter('stop_x_range', [0.0, 1.45]).value
        self.stop_half_width = self.declare_parameter('stop_half_width', 0.45).value
        self.slowdown_x_range = self.declare_parameter(
            'slowdown_x_range', [0.55, 2.6]).value
        self.slowdown_half_width = self.declare_parameter(
            'slowdown_half_width', 0.5).value
        self.sample_stride = self.declare_parameter('sample_stride', 4).value

        self.camera_model = None
        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations, overlay_topic, qos_profile_sensor_data)
        self.create_subscription(
            CameraInfo, camera_info_topic, self.on_camera_info,
            qos_profile_sensor_data)
        self.create_subscription(
            PointCloud2, cloud_topic, self.on_cloud, qos_profile_sensor_data)
        self.get_logger().info(f'collision overlay: {cloud_topic} -> {overlay_topic}')

    def on_camera_info(self, message):
        if self.camera_model is None:
            self.camera_model = PinholeCameraModel()
        self.camera_model.from_camera_info(message)

    def on_cloud(self, message):
        if self.camera_model is None:
            return
        try:
            transform = self.tf_buffer.lookup_transform(
                self.base_frame, message.header.frame_id, rclpy.time.Time())
        except Exception:
            return
        optical_points = read_points_numpy(
            message, field_names=('x', 'y', 'z'), skip_nans=True)
        optical_points = optical_points[::self.sample_stride]
        if optical_points.size == 0:
            self.overlay_publisher.publish(ImageAnnotations())
            return
        base_points = transform_points(optical_points, transform.transform)

        x, y, z = base_points[:, 0], base_points[:, 1], base_points[:, 2]
        in_height_band = (z >= self.min_height) & (z <= self.max_height)
        in_stop = (in_height_band
                   & (x >= self.stop_x_range[0]) & (x <= self.stop_x_range[1])
                   & (np.abs(y) <= self.stop_half_width))
        in_slowdown = (in_height_band & ~in_stop
                       & (x >= self.slowdown_x_range[0])
                       & (x <= self.slowdown_x_range[1])
                       & (np.abs(y) <= self.slowdown_half_width))

        overlay = ImageAnnotations()
        for mask, color in ((in_stop, STOP_COLOR), (in_slowdown, SLOWDOWN_COLOR)):
            zone_points = optical_points[mask][:MAX_POINTS_PER_ZONE]
            zone_forward_distances = x[mask][:MAX_POINTS_PER_ZONE]
            nearest = None
            for optical_point, forward_distance in zip(zone_points, zone_forward_distances):
                if optical_point[2] <= 0.0:
                    continue
                pixel_x, pixel_y = self.camera_model.project_3d_to_pixel(optical_point)
                if not (0 <= pixel_x < self.camera_model.width
                        and 0 <= pixel_y < self.camera_model.height):
                    continue
                marker = CircleAnnotation()
                marker.timestamp = message.header.stamp
                marker.position = Point2(x=float(pixel_x), y=float(pixel_y))
                marker.diameter = POINT_DIAMETER_PX
                marker.thickness = POINT_THICKNESS_PX
                marker.fill_color = color
                marker.outline_color = color
                overlay.circles.append(marker)
                if nearest is None or forward_distance < nearest[0]:
                    nearest = (float(forward_distance), float(pixel_x), float(pixel_y))
            if nearest is not None:
                label = TextAnnotation()
                label.timestamp = message.header.stamp
                label.position = Point2(
                    x=nearest[1],
                    y=max(nearest[2] - LABEL_MARGIN_PX, 0.0))
                label.text = f'{nearest[0]:.1f}m'
                label.font_size = LABEL_FONT_SIZE
                label.text_color = color
                label.background_color = TEXT_BACKGROUND_COLOR
                overlay.texts.append(label)
        self.overlay_publisher.publish(overlay)


def main():
    rclpy.init()
    node = CollisionOverlay()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
