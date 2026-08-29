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


import math
import os
import xml.etree.ElementTree as ElementTree

import yaml
from better_launch import BetterLaunch, launch_this
from better_launch.gazebo import (
    GazeboBridge,
    get_gazebo_axes_args,
    spawn_model,
    spawn_topic_bridge,
)
from jazzy_command import (
    behavior_lifecycle_manager_command,
    behavior_server_command,
    jazzy_environment,
)
from spawn import spawn_robot

WORLD_SPAWN_POSES = {
    'maize': {'x': -14.0, 'y': -19.0, 'z': 0.8, 'yaw': 0.0},
    'plasticulture': {'x': -10.8, 'y': -3.0, 'z': 0.25, 'yaw': 0.0},
}
NAMED_SPAWN_POSES = {
    'farm': {
        'taro': {'x': 11.2, 'y': -0.6, 'z': 0.4, 'yaw': 0.0},
        'jiro': {'x': 0.333, 'y': 0.848, 'z': 0.33, 'yaw': 1.747},
    },
}
KNOWN_WORLDS = frozenset(WORLD_SPAWN_POSES) | frozenset(NAMED_SPAWN_POSES)
DEFAULT_SPAWN_HEIGHT_M = 0.4
ROBOT_SPACING_M = 2.0
PERSON_AHEAD_M = 3.0
PERSON_SPAWN_POSES = {
    'plasticulture': {'x': -14.5, 'y': -3.0},
    'farm': {'x': 6.5, 'y': 3.6},
}


def machine_config(robot):
    with open(f'machines/{robot}/robot.yaml') as file:
        return yaml.safe_load(file)


def ground_offset(urdf_path):
    robot = ElementTree.parse(urdf_path).getroot()
    for joint in robot.iter('joint'):
        child = joint.find('child')
        if child is None or child.get('link') != 'base_footprint':
            continue
        origin = joint.find('origin')
        if origin is None:
            break
        return float(origin.get('xyz', '0 0 0').split()[2])
    return 0.0


def harvest_lane_stack(bl, robot, machine):
    config = machine.get('harvest_lane', {})
    if not config.get('enabled', False):
        return
    camera_mount_xyz = machine['sensors']['camera'][0]['xyz']
    bl.node(
        package='robot_perception',
        executable='canopy_detector',
        name='canopy_detector',
        params={
            'image_topic': 'sensors/camera_0/color/image_raw/compressed',
            'mask_topic': 'perception/canopy/mask/compressed',
            'fraction_topic': 'perception/canopy/fraction',
        } | config.get('detector', {}),
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='harvest_lane_navigator',
        name='harvest_lane_navigator',
        params={
            'mask_topic': 'perception/canopy/mask/compressed',
            'camera_info_topic': 'sensors/camera_0/color/camera_info',
            'depth_topic': 'sensors/camera_0/depth/image_raw',
            'odom_topic': 'diff_drive_controller/odom',
            'camera_height_m': float(camera_mount_xyz[2]) - ground_offset(
                f'mech/urdf/{robot}/robot.sim.urdf'),
            'camera_lateral_offset_m': float(camera_mount_xyz[1]),
            'start_enabled': False,
        } | config.get('navigator', {}),
        max_respawns=-1,
        respawn_delay=2.0,
    )


def jazzy_process(bl, name, command):
    bl.process(
        command,
        name=name,
        env=jazzy_environment(),
        isolate_env=True,
        max_respawns=-1,
        respawn_delay=2.0,
    )


def follow_stack(bl):
    bl.node(
        package='robot_perception',
        executable='person_detector',
        name='person_detector',
        params={
            'image_topic': 'sensors/camera_0/color/image_raw/compressed',
            'depth_topic': 'sensors/camera_0/depth/image_raw',
            'depth_camera_info_topic': 'sensors/camera_0/depth/camera_info',
            'min_score': 0.3,
            'overlay_topic': 'perception/person/overlay',
            'start_enabled': False,
        },
        remaps={'detections': 'perception/person'},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='approach',
        name='person_follow',
        params={
            'standoff_distance': 1.5,
            'max_missing_frames': 8,
            'scene_topic': 'perception/person/scene',
        },
        remaps={
            'detections': 'perception/person',
            'detections_3d': 'perception/targets',
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )


def robot_stack(bl, robot, world, pose, depth_scan):
    machine = machine_config(robot)
    with bl.group(robot):
        spawn_robot(bl, robot, world, depth_scan=depth_scan, **pose)
        bl.node(
            package='twist_mux',
            executable='twist_mux',
            name='twist_mux',
            param_files='control/config/twist_mux.yaml',
            remaps={'cmd_vel_out': 'platform/cmd_vel'},
        )
        harvest_lane_stack(bl, robot, machine)
        follow_stack(bl)
        bl.node(
            package='robot_perception',
            executable='row_shuttle',
            name='row_shuttle',
            max_respawns=-1,
            respawn_delay=2.0,
        )
        jazzy_process(bl, f'{robot}_behavior_server', behavior_server_command(robot))
        jazzy_process(bl, f'{robot}_behavior_lifecycle_manager',
                      behavior_lifecycle_manager_command(robot))


@launch_this(use_sim_time=True)
def simulation(world: str = 'farm', robots: str = 'taro,jiro', headless: bool = False,
               depth_scan: bool = False):
    bl = BetterLaunch()
    bl.process(
        'ros2 run rmw_zenoh_cpp rmw_zenohd',
        name='zenoh_router',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={
            'port': 8765,
            'send_buffer_limit': 1000000,
            'max_qos_depth': 5,
            'best_effort_qos_topic_whitelist': ['.*/sensors/camera_.*'],
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )
    spawn_topic_bridge(GazeboBridge.clock_bridge(), node_name='clock_bridge')
    bl.include('robot_simulator', 'gz_sim.launch.py', world=world, headless=headless)

    if world not in KNOWN_WORLDS:
        raise SystemExit(
            f'unknown world {world!r}; pixi task arguments are positional, so'
            f' write `pixi r -m apps/robot sim <world> <robots>`.'
            f' Known worlds: {", ".join(sorted(KNOWN_WORLDS))}')
    base_pose = dict(WORLD_SPAWN_POSES.get(world, {}))
    spacing = base_pose.pop('spacing', ROBOT_SPACING_M)
    yaw = base_pose.get('yaw', 0.0)
    named_poses = NAMED_SPAWN_POSES.get(world, {})
    names = [name.strip() for name in robots.split(',') if name.strip()]
    for index, robot in enumerate(names):
        if robot in named_poses:
            pose = dict(named_poses[robot])
        else:
            pose = {'z': DEFAULT_SPAWN_HEIGHT_M, 'yaw': yaw, **base_pose}
            pose['x'] = base_pose.get('x', 0.0) - index * spacing * math.sin(yaw)
            pose['y'] = base_pose.get('y', 0.0) + index * spacing * math.cos(yaw)
        robot_stack(bl, robot, world, pose, depth_scan)

    person_pose = PERSON_SPAWN_POSES.get(world, {
        'x': base_pose.get('x', 0.0) + PERSON_AHEAD_M * math.cos(yaw),
        'y': base_pose.get('y', 0.0) + PERSON_AHEAD_M * math.sin(yaw),
    })
    spawn_model(
        'person',
        os.path.abspath('simulation/models/person/model.sdf'), 'file',
        spawn_args=get_gazebo_axes_args(**person_pose))
