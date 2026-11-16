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
from robot_boot.launch_policy import (
    include,
    LIFECYCLE_ACTIVATION,
    RESPAWN,
    TF_REMAPS,
    write_parameter_overrides_file,
)
from robot_boot.urdf import ground_offset_meters
from robot_boot.zenoh_router import ensure_zenoh_router
from robot_machines.machine import load_machine
from robot_simulation.gz_bridges import spawn_depth_laserscans
from robot_simulation.spawn import spawn_robot
from robot_simulation.target import TARGET_AHEAD_METERS, TARGET_SPAWN_POSES

WORLD_SPAWN_POSES = {
    'area_xo': {'x': 35.423, 'y': 24.945, 'z': 0.117, 'yaw': -2.529},
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
DEFAULT_SPAWN_HEIGHT_METERS = 0.4
ROBOT_SPACING_METERS = 2.0
SIMULATION_ROS_PARAMETERS = {'person_follow': {'max_missing_frames': 8}}
DETECTOR_BY_TARGET = {'person': 'person_detector', 'cone': 'color_blob_detector'}
AUTOSTARTED_TARGETS = ('cone',)


def write_simulation_overrides_file(machine):
    ros_parameters = {node: dict(values) for node, values in machine.ros_parameters.items()}
    for node, values in SIMULATION_ROS_PARAMETERS.items():
        ros_parameters.setdefault(node, {}).update(values)
    return write_parameter_overrides_file(ros_parameters)


def robot_stack(bl, machine, world, pose, target):
    camera = machine.sensors.camera[0]
    overrides_file = write_simulation_overrides_file(machine)
    with bl.group(machine.name):
        spawn_robot(bl, machine, world, pose)
        include('robot_boot', 'twist_mux.launch.py')
        if machine.behaviors.harvest_lane:
            include(
                'robot_navigation', 'harvest_lane.launch.py',
                camera_height_meters=float(camera.xyz[2]) - ground_offset_meters(
                    bl.find('robot_description', 'robot.sim.urdf', subdir=f'urdf/{machine.name}')),
                camera_lateral_offset_meters=float(camera.xyz[1]),
                overrides_file=overrides_file,
            )
        include(
            'robot_navigation', 'follow.launch.py',
            image_topic='sensors/camera_0/color/image_raw/compressed',
            detector=DETECTOR_BY_TARGET[target],
            target=target,
            start_enabled=target in AUTOSTARTED_TARGETS,
            overrides_file=overrides_file,
        )
        bl.node(
            package='nav2_behaviors',
            executable='behavior_server',
            name='behavior_server',
            param_files=[bl.find('robot_navigation', 'behaviors.yaml')],
            remaps=TF_REMAPS,
            **RESPAWN,
            **LIFECYCLE_ACTIVATION,
        )


def runs_gps_navigation(machine):
    return bool(
        machine.behaviors.gps_navigation and machine.sensors.gps and machine.depth_camera)


def gps_navigation_stack(machine):
    gps_topic_prefix = f'sensors/{machine.sensors.gps[0].name}'
    include('robot_boot', 'robot_localization.launch.py', gps_topic_prefix=gps_topic_prefix)
    include(
        'robot_navigation', 'ground_station_bridge.launch.py',
        system_id=machine.system.mavlink_system_id,
        gps_topic=f'{gps_topic_prefix}/fix',
    )
    include(
        'robot_boot', 'gps_navigation.launch.py',
        scan_topic=f'sensors/{machine.depth_camera.name}/scan',
        overrides_file=write_simulation_overrides_file(machine),
    )


@launch_this(use_sim_time=True)
def simulation(world: str = 'farm', robots: str = 'taro,jiro', headless: bool = False,
               laserscan_enabled: bool = False, target: str = 'person'):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    include('robot_boot', 'foxglove_bridge.launch.py')
    spawn_topic_bridge(GazeboBridge.clock_bridge(), node_name='clock_bridge')
    bl.include('robot_simulation', 'gz_sim.launch.py', world=world, headless=headless)

    if world not in KNOWN_WORLDS:
        raise SystemExit(
            f'unknown world {world!r}; pixi task arguments are positional, so'
            f' write `pixi r -m apps/robot simulation <world> <robots>`.'
            f' Known worlds: {", ".join(sorted(KNOWN_WORLDS))}')
    base_pose = dict(WORLD_SPAWN_POSES.get(world, {}))
    spacing = base_pose.pop('spacing', ROBOT_SPACING_METERS)
    yaw = base_pose.get('yaw', 0.0)
    named_poses = NAMED_SPAWN_POSES.get(world, {})
    machines = [load_machine(name.strip()) for name in robots.split(',') if name.strip()]
    for index, machine in enumerate(machines):
        if machine.name in named_poses:
            pose = dict(named_poses[machine.name])
        else:
            pose = {'z': DEFAULT_SPAWN_HEIGHT_METERS, 'yaw': yaw, **base_pose}
            pose['x'] = base_pose.get('x', 0.0) - index * spacing * math.sin(yaw)
            pose['y'] = base_pose.get('y', 0.0) + index * spacing * math.cos(yaw)
        robot_stack(bl, machine, world, pose, target)

    target_pose = TARGET_SPAWN_POSES.get(world, {
        'x': base_pose.get('x', 0.0) + TARGET_AHEAD_METERS * math.cos(yaw),
        'y': base_pose.get('y', 0.0) + TARGET_AHEAD_METERS * math.sin(yaw),
    })
    spawn_model(
        target,
        bl.find('robot_simulation', 'model.sdf', subdir=f'models/{target}'), 'file',
        spawn_args=get_gazebo_axes_args(**target_pose))
    for machine in machines:
        if laserscan_enabled or runs_gps_navigation(machine):
            with bl.group(machine.name):
                spawn_depth_laserscans(machine)
                if runs_gps_navigation(machine):
                    gps_navigation_stack(machine)
