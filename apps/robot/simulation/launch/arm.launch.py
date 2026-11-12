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
import re
import subprocess
import tempfile
import threading
import time

from ament_index_python.packages import get_package_share_directory
from ament_index_python.search_paths import get_search_paths
from better_launch import BetterLaunch, launch_this
from better_launch.gazebo import get_gazebo_axes_args, spawn_model
from robot_boot.launch_policy import include
from robot_boot.zenoh_router import ensure_zenoh_router
from robot_machines.machine import load_machine
from robot_simulation.target import TARGET_AHEAD_METERS, TARGET_SPAWN_POSES
from robot_simulation.view_control import set_view_control_sensitivity

ARM_SPAWN_POSES = {'farm': {'x': 11.3, 'y': 3.0}, 'maize': {'x': 0.3, 'y': 16.0}}
GUI_CAMERA_POSE_OFFSET_METERS = (1.8, -1.8, 1.2)
GUI_CAMERA_POSE_OFFSET_RADIANS = (0.0, 0.25, 2.36)
DRAG_MODE_RETRY_DELAY_SECONDS = 2.0
DRAG_MODE_MAX_ATTEMPTS = 60


def activate_drag_mode():
    command = [
        'ros2', 'control', 'switch_controllers',
        '--activate', 'motion_control_handle', 'cartesian_motion_controller',
        '--deactivate', 'joint_trajectory_controller',
    ]
    for _ in range(DRAG_MODE_MAX_ATTEMPTS):
        completed = subprocess.run(command, capture_output=True)
        if completed.returncode == 0:
            return
        time.sleep(DRAG_MODE_RETRY_DELAY_SECONDS)


def write_gui_config_file(bl, gui_camera_pose):
    with open(bl.find('robot_simulation', 'arm_gui.config')) as template:
        gui_config = re.sub(
            r'<camera_pose>[^<]*</camera_pose>',
            '<camera_pose>{} {} {} {} {} {}</camera_pose>'.format(*gui_camera_pose),
            template.read())
    gui_config_tempfile = tempfile.NamedTemporaryFile(mode='w', suffix='.config', delete=False)
    gui_config_tempfile.write(gui_config)
    gui_config_tempfile.close()
    return gui_config_tempfile.name


@launch_this(use_sim_time=True)
def arm(robot: str = 'kinova-link-6', gripper: str = '',
        headless: bool = False, mode: str = 'drag',
        world: str = 'farm'):
    machine = load_machine(robot)
    gripper = gripper or machine.arm.gripper
    spawn_pose = ARM_SPAWN_POSES.get(world, {'x': 0.0, 'y': 0.0})
    spawn_x, spawn_y = spawn_pose['x'], spawn_pose['y']
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)
    simulation_share_directory = get_package_share_directory('robot_simulation')
    share_directories = [
        os.path.join(prefix, 'share') for prefix in get_search_paths()]
    os.environ['GZ_SIM_RESOURCE_PATH'] = ':'.join(filter(None, [
        os.environ.get('GZ_SIM_RESOURCE_PATH', ''),
        *share_directories,
        os.path.join(simulation_share_directory, 'worlds'),
        os.path.join(simulation_share_directory, 'models')]))
    os.environ['GZ_SIM_SYSTEM_PLUGIN_PATH'] = os.path.join(
        os.environ.get('CONDA_PREFIX', ''), 'lib')

    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    if world == 'empty':
        world_file = 'empty.sdf'
    else:
        world_file = bl.find('robot_simulation', f'{world}.sdf', subdir='worlds')
    include(
        machine.arm.bringup_package, 'link6_sim.launch.py',
        gripper=gripper,
        gui='false',
        gz_args=f'-s -r -v 2 {world_file}',
        spawn_x=str(spawn_x),
        spawn_y=str(spawn_y),
    )
    target_pose = TARGET_SPAWN_POSES.get(world, {
        'x': spawn_x + TARGET_AHEAD_METERS,
        'y': spawn_y,
    })
    spawn_model(
        'person',
        bl.find('robot_simulation', 'model.sdf', subdir='models/person'), 'file',
        spawn_args=get_gazebo_axes_args(**target_pose))
    if mode == 'drag':
        threading.Thread(target=activate_drag_mode, daemon=True).start()
    if mode == 'moveit':
        include(
            'robot_manipulation', 'kinova_link6_moveit.launch.py',
            moveit_package=machine.arm.moveit_package,
            motions_file=bl.find('robot_machines', 'motions.yaml', subdir=robot),
            use_sim_time=True,
            rviz_enabled=not headless,
        )
    if not headless:
        gui_camera_pose = (
            spawn_x + GUI_CAMERA_POSE_OFFSET_METERS[0],
            spawn_y + GUI_CAMERA_POSE_OFFSET_METERS[1],
            GUI_CAMERA_POSE_OFFSET_METERS[2],
            *GUI_CAMERA_POSE_OFFSET_RADIANS)
        bl.process(
            ['gz', 'sim', '-g', '--gui-config', write_gui_config_file(bl, gui_camera_pose)],
            name='gazebo_gui',
        )
        threading.Thread(
            target=set_view_control_sensitivity, daemon=True).start()
        if mode != 'moveit':
            bl.process(
                ['rviz2', '-d', bl.find(machine.arm.control_package, 'link6_config.rviz'),
                 '--ros-args', '-p', 'use_sim_time:=true'],
                name='rviz',
            )
