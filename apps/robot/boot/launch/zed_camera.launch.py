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
from machine import ZED_CAMERA_MODEL, load_machine
import yaml

ZED_SDK_ROOT = '/usr/local/zed'

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


def zed_wrapper_defaults(bl, config_name):
    with open(bl.find('zed_wrapper', config_name)) as config_file:
        return yaml.safe_load(config_file)['/**']['ros__parameters']


def deep_merge(base, override):
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def launch_zed_camera(bl, camera, topic_prefix):
    camera_name = camera.node_name
    parameters = zed_wrapper_defaults(bl, 'common_stereo.yaml')
    parameters = deep_merge(parameters, zed_wrapper_defaults(bl, 'zed2.yaml'))
    parameters = deep_merge(parameters, camera.node_parameters)
    parameters = deep_merge(parameters, {
        'general': {'camera_name': camera_name, 'camera_model': 'zed2'},
        'svo': {'svo_path': 'live'},
    })
    tf_remaps = {
        '/tf': f'{topic_prefix}/tf',
        '/tf_static': f'{topic_prefix}/tf_static',
    }
    with bl.compose(f'{camera_name}_container', variant='multithreading'):
        bl.component(
            'zed_components', 'stereolabs::ZedCamera', camera_name,
            params=parameters,
            remaps=tf_remaps | {
                '~/rgb/color/rect/image':
                    f'{topic_prefix}/sensors/{camera_name}/color/image_raw',
                '~/depth/depth_registered':
                    f'{topic_prefix}/sensors/{camera_name}/depth/image_raw',
                '~/point_cloud/cloud_registered':
                    f'{topic_prefix}/sensors/{camera_name}/depth/points',
                '~/image/depth_image':
                    f'{topic_prefix}/sensors/{camera_name}/depth/image_view',
                '~/obj_det/objects':
                    f'{topic_prefix}/sensors/{camera_name}/objects',
                '~/imu/data':
                    f'{topic_prefix}/sensors/{camera_name}/imu/data',
            },
        )
    robot_state_publisher(
        bl.find('zed_description', 'zed_descr.urdf.xacro'),
        node_name=f'{camera_name}_state_publisher',
        xacro_args=[f'camera_name:={camera_name}', 'camera_model:=zed2'],
        remaps=tf_remaps | {
            'robot_description': f'{topic_prefix}/{camera_name}_description',
        },
    )
    xyz = camera.xyz
    rpy = camera.rpy
    bl.node(
        package='tf2_ros',
        executable='static_transform_publisher',
        name=f'{camera_name}_mount_publisher',
        cmd_args=[
            '--x', str(xyz[0]), '--y', str(xyz[1]), '--z', str(xyz[2]),
            '--roll', str(rpy[0]), '--pitch', str(rpy[1]), '--yaw', str(rpy[2]),
            '--frame-id', camera.parent,
            '--child-frame-id', f'{camera_name}_camera_link',
        ],
        remaps=tf_remaps,
        **RESPAWN,
    )
    if parameters.get('object_detection', {}).get('od_enabled', False):
        bl.process(
            'python perception/src/zed_object_overlay.py --ros-args'
            f' -p objects_topic:={topic_prefix}/sensors/{camera_name}/objects'
            f' -p detections_topic:={topic_prefix}/detections'
            ' -p overlay_topic:='
            f'{topic_prefix}/perception/vision/overlay',
            name='zed_object_overlay',
            **RESPAWN,
        )


@launch_this
def zed_camera(robot: str = 'saburo'):
    machine = load_machine(robot)
    namespace = machine.namespace
    topic_prefix = f'/{namespace}' if namespace else ''
    camera = machine.first_enabled_camera(ZED_CAMERA_MODEL)
    if camera is None:
        raise RuntimeError(f'{robot} declares no enabled zed_2 camera')
    if not os.path.isdir(ZED_SDK_ROOT):
        raise RuntimeError(f'{ZED_SDK_ROOT} not found; install the ZED SDK')
    bl = BetterLaunch()
    launch_zed_camera(bl, camera, topic_prefix)
