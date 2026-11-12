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


import os

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher
from robot_boot.launch_policy import RESPAWN, TF_REMAPS
from robot_boot.zenoh_router import ensure_router
import yaml

ZED_SDK_ROOT = os.environ.get('ZED_SDK_ROOT', '/usr/local/zed')


def zed_wrapper_defaults(bl, config_name):
    with open(bl.find('zed_wrapper', config_name)) as config_file:
        return yaml.safe_load(config_file)['/**']['ros__parameters']


def node_overrides(overrides_file, node_name):
    if not overrides_file:
        return {}
    with open(overrides_file) as file:
        return yaml.safe_load(file).get(f'/**/{node_name}', {}).get('ros__parameters', {})


def deep_merge(base, override):
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


@launch_this
def zed_camera(
    camera: str = 'camera_0',
    camera_model: str = 'zed2',
    parent_frame: str = 'base_link',
    x: float = 0.0,
    y: float = 0.0,
    z: float = 0.0,
    roll: float = 0.0,
    pitch: float = 0.0,
    yaw: float = 0.0,
    overrides_file: str = '',
):
    if not os.path.isdir(ZED_SDK_ROOT):
        raise RuntimeError(f'{ZED_SDK_ROOT} not found; install the ZED SDK')
    bl = BetterLaunch()
    ensure_router(bl)
    parameters = zed_wrapper_defaults(bl, 'common_stereo.yaml')
    deep_merge(parameters, zed_wrapper_defaults(bl, f'{camera_model}.yaml'))
    deep_merge(parameters, node_overrides(overrides_file, camera))
    deep_merge(parameters, {
        'general': {'camera_name': camera, 'camera_model': camera_model},
        'svo': {'svo_path': 'live'},
    })
    with bl.compose(f'{camera}_container', variant='multithreading'):
        bl.component(
            'zed_components', 'stereolabs::ZedCamera', camera,
            params=parameters,
            remaps=TF_REMAPS | {
                '~/rgb/color/rect/image': f'sensors/{camera}/color/image_raw',
                '~/depth/depth_registered': f'sensors/{camera}/depth/image_raw',
                '~/point_cloud/cloud_registered': f'sensors/{camera}/depth/points',
                '~/image/depth_image': f'sensors/{camera}/depth/image_view',
                '~/obj_det/objects': f'sensors/{camera}/objects',
                '~/imu/data': f'sensors/{camera}/imu/data',
            },
        )
    robot_state_publisher(
        bl.find('zed_description', 'zed_descr.urdf.xacro'),
        node_name=f'{camera}_state_publisher',
        xacro_args=[f'camera_name:={camera}', f'camera_model:={camera_model}'],
        remaps=TF_REMAPS | {'robot_description': f'{camera}_description'},
    )
    bl.node(
        package='tf2_ros',
        executable='static_transform_publisher',
        name=f'{camera}_mount_publisher',
        cmd_args=[
            '--x', str(x), '--y', str(y), '--z', str(z),
            '--roll', str(roll), '--pitch', str(pitch), '--yaw', str(yaw),
            '--frame-id', parent_frame,
            '--child-frame-id', f'{camera}_camera_link',
        ],
        remaps=TF_REMAPS,
        **RESPAWN,
    )
    if parameters.get('object_detection', {}).get('od_enabled', False):
        bl.node(
            package='robot_perception',
            executable='zed_object_overlay',
            name='zed_object_overlay',
            params={
                'objects_topic': f'sensors/{camera}/objects',
                'detections_topic': 'detections',
                'overlay_topic': 'perception/vision/overlay',
            },
            **RESPAWN,
        )
