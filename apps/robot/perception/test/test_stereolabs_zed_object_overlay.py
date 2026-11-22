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


from foxglove_msgs.msg import PointsAnnotation, SceneEntityDeletion
import pytest
from sensor_msgs.msg import CameraInfo
from zed_msgs.msg import Object, ObjectsStamped

PERSON_POSITION_METERS = (2.0, 0.5, 0.05)
BOX_HALF_LENGTH_METERS = 0.2
BOX_HALF_WIDTH_METERS = 0.3
BOX_TOP_METERS = 0.9
BOX_BOTTOM_METERS = -0.8
BOX_EDGE_COUNT = 12
FOCAL_LENGTH_PIXELS = 500.0
IMAGE_WIDTH_PIXELS = 1280
IMAGE_HEIGHT_PIXELS = 720


@pytest.fixture
def make_tracked_object(stereolabs_zed_object_overlay_module):
    def make(label, sublabel, position=PERSON_POSITION_METERS, label_id=3):
        tracked_object = Object()
        tracked_object.label = label
        tracked_object.sublabel = sublabel
        tracked_object.label_id = label_id
        tracked_object.confidence = 80.0
        tracked_object.position = list(position)
        tracked_object.tracking_available = True
        tracked_object.tracking_state = stereolabs_zed_object_overlay_module.TRACKING_STATE_OK
        for corner, (x, y) in zip(tracked_object.bounding_box_2d.corners,
                                  ((100, 50), (200, 50), (200, 300), (100, 300))):
            corner.kp = [x, y]
        forward, left, _ = position
        top_face = (
            (forward - BOX_HALF_LENGTH_METERS, left + BOX_HALF_WIDTH_METERS),
            (forward + BOX_HALF_LENGTH_METERS, left + BOX_HALF_WIDTH_METERS),
            (forward + BOX_HALF_LENGTH_METERS, left - BOX_HALF_WIDTH_METERS),
            (forward - BOX_HALF_LENGTH_METERS, left - BOX_HALF_WIDTH_METERS),
        )
        corners = tracked_object.bounding_box_3d.corners
        for top_index, (x, y) in enumerate(top_face):
            corners[top_index].kp = [x, y, BOX_TOP_METERS]
            corners[top_index + len(top_face)].kp = [x, y, BOX_BOTTOM_METERS]
        return tracked_object
    return make


@pytest.fixture
def make_person(make_tracked_object):
    def make(**overrides):
        return make_tracked_object('Person', 'Person', **overrides)
    return make


def objects(*tracked_objects):
    message = ObjectsStamped()
    message.header.frame_id = 'camera_0_left_camera_frame'
    message.objects = list(tracked_objects)
    return message


def make_camera_info():
    message = CameraInfo()
    message.width = IMAGE_WIDTH_PIXELS
    message.height = IMAGE_HEIGHT_PIXELS
    message.k = [
        FOCAL_LENGTH_PIXELS, 0.0, IMAGE_WIDTH_PIXELS / 2.0,
        0.0, FOCAL_LENGTH_PIXELS, IMAGE_HEIGHT_PIXELS / 2.0,
        0.0, 0.0, 1.0]
    return message


def capture(node):
    published = {'detections': [], 'overlay': [], 'scene': []}
    node.detections_publisher.publish = published['detections'].append
    node.overlay_publisher.publish = published['overlay'].append
    node.scene_publisher.publish = published['scene'].append
    return published


def calibrate(node):
    node.on_camera_info(make_camera_info())


def test_camera_points_become_optical_points(stereolabs_zed_object_overlay_module):
    point = stereolabs_zed_object_overlay_module.optical_point((2.0, 0.5, 0.1))
    assert (point.x, point.y, point.z) == (-0.5, -0.1, 2.0)


@pytest.mark.parametrize(('label', 'sublabel', 'expected'), [
    ('Person', 'Person', 'human.pedestrian.adult'),
    ('Vehicle', 'Truck', 'vehicle.truck'),
    ('Vehicle', 'Motorbike', 'vehicle.motorcycle'),
    ('Animal', 'Dog', 'animal'),
    ('Bag', 'Backpack', 'bag.backpack'),
])
def test_zed_classes_map_onto_nuscenes_categories(
        stereolabs_zed_object_overlay_module, make_tracked_object, label, sublabel, expected):
    tracked_object = make_tracked_object(label, sublabel)
    assert stereolabs_zed_object_overlay_module.nuscenes_category(tracked_object) == expected


def test_categories_take_the_nuscenes_palette(stereolabs_zed_object_overlay_module):
    cube_alpha = stereolabs_zed_object_overlay_module.CUBE_ALPHA
    color = stereolabs_zed_object_overlay_module.category_color('vehicle.car', cube_alpha)
    assert (color.r, color.g, color.b, color.a) == (
        1.0, pytest.approx(158 / 255), 0.0, cube_alpha)


def test_detections_carry_the_optical_position_follow_steers_by(
        stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(objects(make_person()))
    detections = published['detections'][0]
    assert detections.header.frame_id == 'camera_0_left_camera_frame_optical'
    hypothesis = detections.detections[0].results[0]
    assert hypothesis.hypothesis.class_id == 'person'
    assert hypothesis.pose.pose.position.z == pytest.approx(2.0)


def test_each_object_becomes_a_translucent_cube_in_its_category_color(
        stereolabs_zed_object_overlay_module, stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(objects(make_person(label_id=7)))
    entity = published['scene'][0].entities[0]
    assert (entity.frame_id, entity.id, entity.frame_locked) == (
        'camera_0_left_camera_frame', '7', True)
    assert entity.metadata[0].value == 'human.pedestrian.adult'
    cube = entity.cubes[0]
    assert (cube.pose.position.x, cube.pose.position.y) == pytest.approx(
        PERSON_POSITION_METERS[:2])
    assert (cube.pose.orientation.x, cube.pose.orientation.y,
            cube.pose.orientation.z, cube.pose.orientation.w) == pytest.approx((0, 0, 0, 1))
    assert (cube.size.x, cube.size.y, cube.size.z) == pytest.approx((0.4, 0.6, 1.7))
    assert (cube.color.b, cube.color.a) == (
        pytest.approx(230 / 255), stereolabs_zed_object_overlay_module.CUBE_ALPHA)


def test_each_update_clears_boxes_of_objects_that_left_view(
        stereolabs_zed_object_overlay_node):
    published = capture(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(objects())
    scene = published['scene'][0]
    assert scene.deletions[0].type == SceneEntityDeletion.ALL
    assert scene.entities == []


def test_box_edges_are_projected_onto_the_image_with_the_category_name(
        stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    calibrate(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(objects(make_person()))
    annotations = published['overlay'][0]
    edges = annotations.points[0]
    assert edges.type == PointsAnnotation.LINE_LIST
    assert len(edges.points) == 2 * BOX_EDGE_COUNT
    category_text = annotations.texts[0]
    assert category_text.text == 'human.pedestrian.adult'
    nearest_depth_meters = PERSON_POSITION_METERS[0] - BOX_HALF_LENGTH_METERS
    leftmost_offset_meters = PERSON_POSITION_METERS[1] + BOX_HALF_WIDTH_METERS
    assert category_text.position.x == pytest.approx(
        IMAGE_WIDTH_PIXELS / 2.0
        - FOCAL_LENGTH_PIXELS * leftmost_offset_meters / nearest_depth_meters)
    assert category_text.position.y == pytest.approx(
        IMAGE_HEIGHT_PIXELS / 2.0
        - FOCAL_LENGTH_PIXELS * BOX_TOP_METERS / nearest_depth_meters)
    assert category_text.background_color.a == 0.0


def test_boxes_reaching_behind_the_camera_are_not_drawn_on_the_image(
        stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    calibrate(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(
        objects(make_person(position=(0.0, 0.5, 0.05))))
    assert published['overlay'][0].points == []


def test_nothing_is_drawn_on_the_image_before_calibration_arrives(
        stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    stereolabs_zed_object_overlay_node.on_objects(objects(make_person()))
    assert published['overlay'][0].points == []


def test_objects_without_a_3d_box_still_get_a_detection(
        stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    person_without_box = make_person()
    for corner in person_without_box.bounding_box_3d.corners:
        corner.kp = [0.0, 0.0, 0.0]
    stereolabs_zed_object_overlay_node.on_objects(objects(person_without_box))
    assert published['scene'][0].entities == []
    assert len(published['detections'][0].detections) == 1


def test_lost_objects_are_not_drawn(
        stereolabs_zed_object_overlay_module, stereolabs_zed_object_overlay_node, make_person):
    published = capture(stereolabs_zed_object_overlay_node)
    lost_person = make_person()
    lost_person.tracking_state = stereolabs_zed_object_overlay_module.TRACKING_STATE_OFF
    stereolabs_zed_object_overlay_node.on_objects(objects(lost_person))
    assert published['scene'][0].entities == []
    assert published['detections'][0].detections == []
