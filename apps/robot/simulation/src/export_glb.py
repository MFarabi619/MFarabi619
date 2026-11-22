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


import argparse
import math
from pathlib import Path

from ament_index_python.packages import get_package_share_path
from resource_retriever import get_filename
from robot_boot.arm_description import write_urdf_file_with_arms
from robot_machines.machine import load_machine
import trimesh
from trimesh.visual.color import srgb_to_linear
import yaml
import yourdfpy

ROBOT_ROOT = Path(__file__).resolve().parents[2]
MESHES_DIRECTORY = ROBOT_ROOT / 'assets' / 'meshes'
POSES_FILE = ROBOT_ROOT / 'machines' / 'kinova-link-6' / 'pick_poses.yaml'
EXPORT_POSE_NAME = 'home'
Z_UP_TO_GLTF_Y_UP_ROTATION = trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0])


def to_linear_rgba(srgb_rgba):
    linear_rgba = srgb_to_linear(srgb_rgba)
    linear_rgba[..., 3] = srgb_rgba[..., 3] / 255.0
    return linear_rgba


def convert_colors_to_linear(scene):
    for mesh in scene.geometry.values():
        if mesh.visual.kind == 'face':
            mesh.visual.face_colors = to_linear_rgba(mesh.visual.face_colors)
        elif getattr(mesh.visual, 'material', None) is not None:
            mesh.visual.material.baseColorFactor = to_linear_rgba(
                mesh.visual.material.baseColorFactor)


def arm_joint_positions_radians(arms):
    joint_positions_degrees = yaml.safe_load(POSES_FILE.read_text())[EXPORT_POSE_NAME]
    return {
        f'{arm.name}_joint_{joint_number}': math.radians(angle_degrees)
        for arm in arms
        for joint_number, angle_degrees in enumerate(joint_positions_degrees, start=1)
    }


def export_glb(robot_name):
    arms = load_machine(robot_name).manipulators.arms
    urdf_path = write_urdf_file_with_arms(
        str(get_package_share_path('robot_description') / 'urdf' / robot_name / 'robot.sim.urdf'),
        arms, 'gazebo')
    urdf = yourdfpy.URDF.load(
        urdf_path, filename_handler=lambda fname: get_filename(fname, use_protocol=False))
    urdf.update_cfg(arm_joint_positions_radians(arms))
    scene = urdf.scene
    convert_colors_to_linear(scene)
    scene.apply_transform(Z_UP_TO_GLTF_Y_UP_ROTATION)
    glb_path = MESHES_DIRECTORY / f'{robot_name}.glb'
    scene.export(glb_path)
    return glb_path


def main():
    parser = argparse.ArgumentParser(description='Export a robot description as a glTF binary.')
    parser.add_argument('robot')
    print(export_glb(parser.parse_args().robot))


if __name__ == '__main__':
    main()
