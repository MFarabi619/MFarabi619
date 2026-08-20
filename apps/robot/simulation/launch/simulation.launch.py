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
ROBOT_SPACING_M = 2.0
PERSON_AHEAD_M = 3.0
PERSON_SPAWN_POSES = {
    'plasticulture': {'x': -14.5, 'y': -3.0},
}


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
    with bl.group(robot):
        spawn_robot(bl, robot, world, depth_scan=depth_scan, **pose)
        bl.node(
            package='twist_mux',
            executable='twist_mux',
            name='twist_mux',
            param_files='control/config/twist_mux.yaml',
            remaps={'cmd_vel_out': 'platform/cmd_vel'},
        )
        bl.node(
            package='robot_perception',
            executable='canopy_detector',
            name='canopy_detector',
            max_respawns=-1,
            respawn_delay=2.0,
        )
        bl.node(
            package='robot_perception',
            executable='harvest_lane_navigator',
            name='harvest_lane_navigator',
            params={'drive_enabled': False},
            max_respawns=-1,
            respawn_delay=2.0,
        )
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
def simulation(world: str = 'plasticulture', robots: str = 'taro', headless: bool = False,
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

    base_pose = WORLD_SPAWN_POSES.get(world, {})
    names = [name.strip() for name in robots.split(',') if name.strip()]
    for index, robot in enumerate(names):
        pose = dict(base_pose)
        pose['y'] = base_pose.get('y', 0.0) + index * ROBOT_SPACING_M
        robot_stack(bl, robot, world, pose, depth_scan)

    yaw = base_pose.get('yaw', 0.0)
    person_pose = PERSON_SPAWN_POSES.get(world, {
        'x': base_pose.get('x', 0.0) + PERSON_AHEAD_M * math.cos(yaw),
        'y': base_pose.get('y', 0.0) + PERSON_AHEAD_M * math.sin(yaw),
    })
    spawn_model(
        'person',
        os.path.abspath('simulation/models/person/model.sdf'), 'file',
        spawn_args=get_gazebo_axes_args(**person_pose))
