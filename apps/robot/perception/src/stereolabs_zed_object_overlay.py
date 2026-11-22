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
    Color,
    CubePrimitive,
    ImageAnnotations,
    KeyValuePair,
    Point2,
    PointsAnnotation,
    SceneEntity,
    SceneEntityDeletion,
    SceneUpdate,
    TextAnnotation,
)
from geometry_msgs.msg import Point, Pose, Quaternion, Vector3
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from scipy.spatial.transform import Rotation
from sensor_msgs.msg import CameraInfo
from vision_msgs.msg import (
    BoundingBox2D,
    Detection2D,
    Detection2DArray,
    ObjectHypothesisWithPose,
    Point2D,
    Pose2D,
)
from zed_msgs.msg import ObjectsStamped

# RGB values from nuscenes-devkit utils/color_map.py, so boxes match the nuScenes demo.
NUSCENES_CATEGORY_COLORS = {
    'animal': (70, 130, 180),
    'human.pedestrian.adult': (0, 0, 230),
    'vehicle.bicycle': (220, 20, 60),
    'vehicle.bus.rigid': (255, 69, 0),
    'vehicle.car': (255, 158, 0),
    'vehicle.construction': (233, 150, 70),
    'vehicle.motorcycle': (255, 61, 99),
    'vehicle.truck': (255, 99, 71),
    'static.other': (255, 228, 196),
}
UNMAPPED_CATEGORY_COLOR = NUSCENES_CATEGORY_COLORS['static.other']
ZED_SUBCLASS_CATEGORIES = {
    'person': 'human.pedestrian.adult',
    'bicycle': 'vehicle.bicycle',
    'car': 'vehicle.car',
    'motorbike': 'vehicle.motorcycle',
    'bus': 'vehicle.bus.rigid',
    'truck': 'vehicle.truck',
    'machinery': 'vehicle.construction',
    'bird': 'animal',
    'cat': 'animal',
    'dog': 'animal',
    'horse': 'animal',
    'sheep': 'animal',
    'cow': 'animal',
}
ZED_CLASS_CATEGORIES = {
    'person': 'human.pedestrian.adult',
    'animal': 'animal',
}

MAX_COLOR_CHANNEL_VALUE = 255.0
CUBE_ALPHA = 0.5
IMAGE_ANNOTATION_ALPHA = 1.0
IMAGE_BOX_THICKNESS_PIXELS = 2.0
IMAGE_LABEL_FONT_SIZE_PIXELS = 24.0
TEXT_BACKGROUND_COLOR = Color(r=1.0, g=1.0, b=1.0, a=0.0)
MIN_VISIBLE_DEPTH_METERS = 1.0
MIN_IN_FRONT_DEPTH_METERS = 0.1
MIN_EDGE_LENGTH_METERS = 1e-6
TRACKING_STATE_OFF = 0
TRACKING_STATE_OK = 1
TRACKING_STATE_SEARCHING = 2
MAX_ZED_CONFIDENCE = 100.0
ZED_OPTICAL_FRAME_SUFFIX = '_optical'
BOX_EDGES = (
    (0, 1), (1, 2), (2, 3), (3, 0),
    (4, 5), (5, 6), (6, 7), (7, 4),
    (0, 4), (1, 5), (2, 6), (3, 7),
)


def is_tracked(tracked_object):
    return not tracked_object.tracking_available or tracked_object.tracking_state in (
        TRACKING_STATE_OK, TRACKING_STATE_SEARCHING)


def snake_case(zed_name):
    return zed_name.strip().lower().replace(' ', '_')


def nuscenes_category(tracked_object):
    zed_class = snake_case(tracked_object.label)
    zed_subclass = snake_case(tracked_object.sublabel)
    category = ZED_SUBCLASS_CATEGORIES.get(zed_subclass) or ZED_CLASS_CATEGORIES.get(zed_class)
    if category:
        return category
    return f'{zed_class}.{zed_subclass}' if zed_subclass else zed_class


def category_color(category, alpha):
    red, green, blue = (
        channel / MAX_COLOR_CHANNEL_VALUE
        for channel in NUSCENES_CATEGORY_COLORS.get(category, UNMAPPED_CATEGORY_COLOR))
    return Color(r=red, g=green, b=blue, a=alpha)


def category_metadata(category):
    return [KeyValuePair(key='category', value=category)]


def optical_from_camera(camera_points):
    camera_points = np.asarray(camera_points, dtype=float)
    forward, left, up = camera_points[..., 0], camera_points[..., 1], camera_points[..., 2]
    return np.stack((-left, -up, forward), axis=-1)


def optical_point(position):
    x, y, z = optical_from_camera(position)
    return Point(x=float(x), y=float(y), z=float(z))


def box_corners(tracked_object):
    corners = np.array(
        [corner.kp for corner in tracked_object.bounding_box_3d.corners], dtype=float)
    if not corners.any():
        return None
    return corners


def cube_primitive(corners, color):
    up_edge = corners[0] - corners[4]
    length_edge = corners[1] - corners[0]
    width_edge = corners[3] - corners[0]
    height_meters = np.linalg.norm(up_edge)
    length_meters = np.linalg.norm(length_edge)
    width_meters = np.linalg.norm(width_edge)
    if min(height_meters, length_meters, width_meters) < MIN_EDGE_LENGTH_METERS:
        return None
    z_axis = up_edge / height_meters
    x_axis = length_edge - length_edge.dot(z_axis) * z_axis
    x_axis /= np.linalg.norm(x_axis)
    y_axis = np.cross(z_axis, x_axis)
    qx, qy, qz, qw = Rotation.from_matrix(np.column_stack((x_axis, y_axis, z_axis))).as_quat()
    center = corners.mean(axis=0)
    return CubePrimitive(
        pose=Pose(
            position=Point(x=float(center[0]), y=float(center[1]), z=float(center[2])),
            orientation=Quaternion(x=float(qx), y=float(qy), z=float(qz), w=float(qw))),
        size=Vector3(x=float(length_meters), y=float(width_meters), z=float(height_meters)),
        color=color)


def project_into_image(corners, camera_info):
    optical_corners = optical_from_camera(corners)
    depths_meters = optical_corners[:, 2]
    if not (depths_meters > MIN_IN_FRONT_DEPTH_METERS).all():
        return None
    camera_matrix = np.array(camera_info.k, dtype=float).reshape(3, 3)
    homogeneous_pixels = optical_corners @ camera_matrix.T
    pixels = homogeneous_pixels[:, :2] / homogeneous_pixels[:, 2:3]
    is_visible = (
        (pixels[:, 0] > 0) & (pixels[:, 0] < camera_info.width)
        & (pixels[:, 1] > 0) & (pixels[:, 1] < camera_info.height)
        & (depths_meters > MIN_VISIBLE_DEPTH_METERS))
    return pixels if is_visible.any() else None


class StereolabsZedObjectOverlay(Node):
    def __init__(self):
        super().__init__('stereolabs_zed_object_overlay')
        self.declare_parameter('objects_topic', 'sensors/camera_0/objects')
        self.declare_parameter('camera_info_topic', 'sensors/camera_0/color/camera_info')
        self.declare_parameter('detections_topic', 'detections')
        self.declare_parameter('overlay_topic', 'perception/vision/overlay')
        self.declare_parameter('scene_topic', 'perception/vision/objects')
        self.camera_info = None
        self.detections_publisher = self.create_publisher(
            Detection2DArray,
            self.get_parameter('detections_topic').value,
            qos_profile_sensor_data)
        self.overlay_publisher = self.create_publisher(
            ImageAnnotations,
            self.get_parameter('overlay_topic').value,
            qos_profile_sensor_data)
        self.scene_publisher = self.create_publisher(
            SceneUpdate,
            self.get_parameter('scene_topic').value,
            qos_profile_sensor_data)
        objects_topic = self.get_parameter('objects_topic').value
        self.create_subscription(
            ObjectsStamped, objects_topic, self.on_objects,
            qos_profile_sensor_data)
        self.create_subscription(
            CameraInfo, self.get_parameter('camera_info_topic').value, self.on_camera_info,
            qos_profile_sensor_data)
        self.get_logger().info(f'zed object overlay: {objects_topic}')

    def on_camera_info(self, message):
        self.camera_info = message

    def on_objects(self, message):
        detections = Detection2DArray()
        detections.header.stamp = message.header.stamp
        detections.header.frame_id = message.header.frame_id + ZED_OPTICAL_FRAME_SUFFIX
        overlay = ImageAnnotations()
        scene = SceneUpdate()
        scene.deletions.append(SceneEntityDeletion(
            timestamp=message.header.stamp, type=SceneEntityDeletion.ALL))
        for tracked_object in filter(is_tracked, message.objects):
            detection = self.detection(detections.header, tracked_object)
            if detection is not None:
                detections.detections.append(detection)
            corners = box_corners(tracked_object)
            if corners is None:
                continue
            category = nuscenes_category(tracked_object)
            entity = self.object_entity(message.header, tracked_object, corners, category)
            if entity is not None:
                scene.entities.append(entity)
            self.annotate(overlay, message.header.stamp, corners, category)
        self.detections_publisher.publish(detections)
        self.overlay_publisher.publish(overlay)
        self.scene_publisher.publish(scene)

    def detection(self, header, tracked_object):
        image_corners = tracked_object.bounding_box_2d.corners
        left = float(image_corners[0].kp[0])
        top = float(image_corners[0].kp[1])
        right = float(image_corners[2].kp[0])
        bottom = float(image_corners[2].kp[1])
        if right <= left or bottom <= top:
            return None
        detection = Detection2D()
        detection.header = header
        detection.id = str(tracked_object.label_id)
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(
                x=(left + right) / 2.0, y=(top + bottom) / 2.0)),
            size_x=right - left,
            size_y=bottom - top)
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = snake_case(tracked_object.label)
        hypothesis.hypothesis.score = tracked_object.confidence / MAX_ZED_CONFIDENCE
        hypothesis.pose.pose.position = optical_point(tracked_object.position)
        detection.results.append(hypothesis)
        return detection

    def object_entity(self, header, tracked_object, corners, category):
        cube = cube_primitive(corners, category_color(category, CUBE_ALPHA))
        if cube is None:
            return None
        return SceneEntity(
            timestamp=header.stamp,
            frame_id=header.frame_id,
            id=str(tracked_object.label_id),
            frame_locked=True,
            metadata=category_metadata(category),
            cubes=[cube])

    def annotate(self, overlay, stamp, corners, category):
        if self.camera_info is None:
            return
        pixels = project_into_image(corners, self.camera_info)
        if pixels is None:
            return
        color = category_color(category, IMAGE_ANNOTATION_ALPHA)
        overlay.points.append(PointsAnnotation(
            timestamp=stamp,
            type=PointsAnnotation.LINE_LIST,
            thickness=IMAGE_BOX_THICKNESS_PIXELS,
            points=[
                Point2(x=float(pixels[index][0]), y=float(pixels[index][1]))
                for edge in BOX_EDGES for index in edge],
            outline_color=color,
            metadata=category_metadata(category)))
        overlay.texts.append(TextAnnotation(
            timestamp=stamp,
            font_size=IMAGE_LABEL_FONT_SIZE_PIXELS,
            position=Point2(x=float(pixels[:, 0].min()), y=float(pixels[:, 1].min())),
            text=category,
            text_color=color,
            background_color=TEXT_BACKGROUND_COLOR))


def main():
    rclpy.init()
    node = StereolabsZedObjectOverlay()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
