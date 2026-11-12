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

from better_launch import BetterLaunch, launch_this
from better_launch.gazebo import (
    GazeboBridge,
    get_gazebo_axes_args,
    spawn_model,
    spawn_topic_bridge,
)
from robot_boot.launch_policy import RESPAWN, include, parameter_overrides_file
from robot_boot.urdf import ground_offset
from robot_boot.zenoh_router import ensure_router
from robot_machines.machine import load_machine
from robot_simulator.spawn import spawn_robot

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
SIM_FOXGLOVE_SEND_BUFFER_LIMIT_BYTES = 1000000
SIM_PERSON_FOLLOW_OVERRIDES = {'person_follow': {'max_missing_frames': 8}}


def robot_stack(bl, robot, world, pose, depth_scan):
    machine = load_machine(robot)
    camera = machine.sensors.camera[0]
    with bl.group(robot):
        spawn_robot(bl, machine, world, depth_scan=depth_scan, **pose)
        include('robot_boot', 'twist_mux.launch.py')
        if machine.behaviors.harvest_lane:
            include(
                'robot_perception', 'harvest_lane.launch.py',
                camera_height_m=float(camera.xyz[2]) - ground_offset(
                    bl.find('robot_description', 'robot.sim.urdf', subdir=f'urdf/{robot}')),
                camera_lateral_offset_m=float(camera.xyz[1]),
                overrides_file=machine.params_file('harvest_lane'),
            )
        include(
            'robot_perception', 'person_follow.launch.py',
            image_topic='sensors/camera_0/color/image_raw/compressed',
            overrides_file=parameter_overrides_file(SIM_PERSON_FOLLOW_OVERRIDES),
        )
        bl.node(
            package='robot_perception',
            executable='row_shuttle',
            name='row_shuttle',
            **RESPAWN,
        )
        bl.node(
            package='nav2_behaviors',
            executable='behavior_server',
            name='behavior_server',
            param_files=[bl.find('robot_navigation', 'behaviors.yaml')],
            **RESPAWN,
        )


@launch_this(use_sim_time=True)
def simulation(world: str = 'farm', robots: str = 'taro,jiro', headless: bool = False,
               depth_scan: bool = False):
    bl = BetterLaunch()
    ensure_router(bl)
    include(
        'robot_boot', 'foxglove_bridge.launch.py',
        send_buffer_limit_bytes=SIM_FOXGLOVE_SEND_BUFFER_LIMIT_BYTES)
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
        bl.find('robot_simulator', 'model.sdf', subdir='models/person'), 'file',
        spawn_args=get_gazebo_axes_args(**person_pose))
