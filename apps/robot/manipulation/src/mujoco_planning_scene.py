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


from pathlib import Path

from geometry_msgs.msg import Point, Pose
from moveit_msgs.msg import (AllowedCollisionEntry, CollisionObject,
                             ObjectColor, PlanningScene,
                             PlanningSceneComponents)
from moveit_msgs.srv import ApplyPlanningScene, GetPlanningScene
from mujoco_ros2_control_msgs.msg import FreeJointStateArray
import rclpy
from rclpy.node import Node
from shape_msgs.msg import Mesh, MeshTriangle
from std_msgs.msg import ColorRGBA
import trimesh
from trimesh import transformations

PLANNING_FRAME = 'world'
PUBLISH_RATE_HZ = 2.0
MOVE_EPSILON_METERS = 0.002
MOVE_EPSILON_QUATERNION = 0.002
MISSING_MODEL_WARNING_THROTTLE_SECONDS = 30.0
GRIPPER_TOUCH_LINKS = [
    'robotiq_85_base_link',
    'robotiq_85_left_knuckle_link',
    'robotiq_85_right_knuckle_link',
    'robotiq_85_left_finger_link',
    'robotiq_85_right_finger_link',
    'robotiq_85_left_inner_knuckle_link',
    'robotiq_85_right_inner_knuckle_link',
    'robotiq_85_left_finger_tip_link',
    'robotiq_85_right_finger_tip_link',
]
BODY_MODELS = {
    'apple': {
        'file': 'simulation/models/ycb/013_apple/google_16k/nontextured.stl',
        'color': (0.72, 0.08, 0.12, 1.0),
    },
}


def load_centered_mesh(path):
    source_mesh = trimesh.load(path)
    centroid = source_mesh.centroid.copy()
    source_mesh.apply_translation(-centroid)
    mesh = Mesh()
    mesh.vertices = [
        Point(x=float(vertex[0]), y=float(vertex[1]), z=float(vertex[2]))
        for vertex in source_mesh.vertices]
    mesh.triangles = [
        MeshTriangle(vertex_indices=[int(face[0]), int(face[1]), int(face[2])])
        for face in source_mesh.faces]
    return mesh, centroid


def centered_object_pose(body_pose, centroid):
    rotation = transformations.quaternion_matrix([
        body_pose.orientation.w, body_pose.orientation.x,
        body_pose.orientation.y, body_pose.orientation.z])
    offset = rotation[:3, :3] @ centroid
    return Pose(
        position=Point(
            x=body_pose.position.x + float(offset[0]),
            y=body_pose.position.y + float(offset[1]),
            z=body_pose.position.z + float(offset[2])),
        orientation=body_pose.orientation)


def poses_match(first, second):
    translation_delta = max(
        abs(first.position.x - second.position.x),
        abs(first.position.y - second.position.y),
        abs(first.position.z - second.position.z))
    rotation_delta = max(
        abs(first.orientation.x - second.orientation.x),
        abs(first.orientation.y - second.orientation.y),
        abs(first.orientation.z - second.orientation.z),
        abs(first.orientation.w - second.orientation.w))
    return (translation_delta <= MOVE_EPSILON_METERS
            and rotation_delta <= MOVE_EPSILON_QUATERNION)


class MujocoPlanningScene(Node):
    def __init__(self):
        super().__init__('mujoco_planning_scene')
        self.latest_poses = {}
        self.published_poses = {}
        self.added_objects = set()
        self.adding_objects = set()
        self.attached_objects = set()
        robot_root = Path(__file__).resolve().parents[2]
        self.meshes = {}
        self.centroids = {}
        for name, model in BODY_MODELS.items():
            self.meshes[name], self.centroids[name] = load_centered_mesh(
                robot_root / model['file'])
        self.scene_publisher = self.create_publisher(
            PlanningScene, 'planning_scene', 10)
        self.scene_applier = self.create_client(
            ApplyPlanningScene, 'apply_planning_scene')
        self.scene_reader = self.create_client(
            GetPlanningScene, 'get_planning_scene')
        self.create_subscription(
            FreeJointStateArray,
            'free_joint_state_publisher/free_joint_states',
            self.on_free_joint_states, 10)
        self.create_subscription(
            PlanningScene, 'monitored_planning_scene',
            self.on_monitored_scene, 10)
        self.create_timer(1.0 / PUBLISH_RATE_HZ, self.publish_scene)

    def on_free_joint_states(self, message):
        for state in message.free_joints:
            self.latest_poses[state.name] = state.pose.pose

    def on_monitored_scene(self, message):
        for attached_object in message.robot_state.attached_collision_objects:
            if attached_object.object.operation == CollisionObject.ADD:
                self.attached_objects.add(attached_object.object.id)
            elif attached_object.object.operation == CollisionObject.REMOVE:
                self.attached_objects.discard(attached_object.object.id)
                self.added_objects.discard(attached_object.object.id)

    def publish_scene(self):
        if not self.latest_poses:
            return
        scene_diff = PlanningScene()
        scene_diff.is_diff = True
        for name, pose in self.latest_poses.items():
            model = BODY_MODELS.get(name)
            if model is None:
                self.get_logger().warning(
                    f'no model registered for free body {name!r}',
                    throttle_duration_sec=MISSING_MODEL_WARNING_THROTTLE_SECONDS)
                continue
            if name in self.attached_objects:
                continue
            if name in self.added_objects:
                if poses_match(pose, self.published_poses[name]):
                    continue
                self.published_poses[name] = pose
                collision_object = CollisionObject()
                collision_object.header.frame_id = PLANNING_FRAME
                collision_object.id = name
                collision_object.operation = CollisionObject.MOVE
                collision_object.pose = centered_object_pose(
                    pose, self.centroids[name])
                scene_diff.world.collision_objects.append(collision_object)
            else:
                self.add_object(name, model, pose)
        if scene_diff.world.collision_objects:
            self.scene_publisher.publish(scene_diff)

    def add_object(self, name, model, pose):
        if (name in self.adding_objects
                or not self.scene_applier.service_is_ready()
                or not self.scene_reader.service_is_ready()):
            return
        self.adding_objects.add(name)
        request = GetPlanningScene.Request()
        request.components.components = (
            PlanningSceneComponents.ALLOWED_COLLISION_MATRIX)
        future = self.scene_reader.call_async(request)
        future.add_done_callback(
            lambda future, name=name, model=model, pose=pose:
                self.on_collision_matrix(name, model, pose, future))

    def on_collision_matrix(self, name, model, pose, future):
        if future.exception() is not None:
            self.adding_objects.discard(name)
            return
        matrix = future.result().scene.allowed_collision_matrix
        if name not in matrix.entry_names:
            touch_row = AllowedCollisionEntry()
            touch_row.enabled = [
                entry_name in GRIPPER_TOUCH_LINKS
                for entry_name in matrix.entry_names]
            touch_row.enabled.append(False)
            for entry_name, entry in zip(
                    matrix.entry_names, matrix.entry_values):
                entry.enabled.append(entry_name in GRIPPER_TOUCH_LINKS)
            matrix.entry_names.append(name)
            matrix.entry_values.append(touch_row)
        collision_object = CollisionObject()
        collision_object.header.frame_id = PLANNING_FRAME
        collision_object.id = name
        collision_object.operation = CollisionObject.ADD
        collision_object.meshes.append(self.meshes[name])
        collision_object.mesh_poses.append(Pose())
        collision_object.pose = centered_object_pose(
            pose, self.centroids[name])
        red, green, blue, alpha = model['color']
        color = ObjectColor(
            id=name, color=ColorRGBA(r=red, g=green, b=blue, a=alpha))
        request = ApplyPlanningScene.Request()
        request.scene.is_diff = True
        request.scene.world.collision_objects.append(collision_object)
        request.scene.object_colors.append(color)
        request.scene.allowed_collision_matrix = matrix
        apply_future = self.scene_applier.call_async(request)
        apply_future.add_done_callback(
            lambda apply_future, name=name:
                self.on_object_added(name, apply_future))

    def on_object_added(self, name, future):
        self.adding_objects.discard(name)
        if future.exception() is None and future.result().success:
            self.added_objects.add(name)
            self.published_poses[name] = self.latest_poses[name]


def main():
    rclpy.init()
    node = MujocoPlanningScene()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
