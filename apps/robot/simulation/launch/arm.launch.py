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
from robot_boot.zenoh_router import ensure_router
from robot_machines.machine import load_machine

WORLD_SPAWN_POINTS = {'farm': (11.3, 3.0), 'maize': (0.3, 16.0)}
PERSON_AHEAD_M = 3.0
PERSON_SPAWN_POSES = {
    'plasticulture': {'x': -14.5, 'y': -3.0},
    'farm': {'x': 6.5, 'y': 3.6},
}
CAMERA_OFFSET = (1.8, -1.8, 1.2, 0.0, 0.25, 2.36)
VIEW_CONTROL_SENSITIVITY = 0.25
SENSITIVITY_RETRY_DELAY_S = 2.0
SENSITIVITY_MAX_ATTEMPTS = 60
DRAG_MODE_RETRY_DELAY_S = 2.0
DRAG_MODE_MAX_ATTEMPTS = 60


def activate_drag_mode():
    command = [
        'ros2', 'control', 'switch_controllers',
        '--activate', 'motion_control_handle', 'cartesian_motion_controller',
        '--deactivate', 'joint_trajectory_controller',
    ]
    for _ in range(DRAG_MODE_MAX_ATTEMPTS):
        result = subprocess.run(command, capture_output=True)
        if result.returncode == 0:
            return
        time.sleep(DRAG_MODE_RETRY_DELAY_S)


def calm_view_control_sensitivity():
    command = [
        'gz', 'service', '-s', '/gui/camera/view_control/sensitivity',
        '--reqtype', 'gz.msgs.Double', '--reptype', 'gz.msgs.Boolean',
        '--timeout', '1000', '--req', f'data: {VIEW_CONTROL_SENSITIVITY}',
    ]
    for _ in range(SENSITIVITY_MAX_ATTEMPTS):
        result = subprocess.run(command, capture_output=True)
        if result.returncode == 0:
            return
        time.sleep(SENSITIVITY_RETRY_DELAY_S)


def gui_config_with_camera(bl, camera):
    with open(bl.find('robot_simulator', 'arm_gui.config')) as template:
        gui_config = re.sub(
            r'<camera_pose>[^<]*</camera_pose>',
            '<camera_pose>{} {} {} {} {} {}</camera_pose>'.format(*camera),
            template.read())
    gui_config_file = tempfile.NamedTemporaryFile(mode='w', suffix='.config', delete=False)
    gui_config_file.write(gui_config)
    gui_config_file.close()
    return gui_config_file.name


@launch_this(use_sim_time=True)
def arm_simulation(robot: str = 'kinova-link-6', gripper: str = '',
                   headless: bool = False, mode: str = 'drag',
                   world: str = 'farm'):
    machine = load_machine(robot)
    arm = machine.arm
    gripper = gripper or arm.gripper
    spawn_x, spawn_y = WORLD_SPAWN_POINTS.get(world, (0.0, 0.0))
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)
    simulator_share = get_package_share_directory('robot_simulator')
    share_directories = [
        os.path.join(prefix, 'share') for prefix in get_search_paths()]
    os.environ['GZ_SIM_RESOURCE_PATH'] = ':'.join(filter(None, [
        os.environ.get('GZ_SIM_RESOURCE_PATH', ''),
        *share_directories,
        os.path.join(simulator_share, 'worlds'),
        os.path.join(simulator_share, 'models')]))
    os.environ['GZ_SIM_SYSTEM_PLUGIN_PATH'] = os.path.join(
        os.environ.get('CONDA_PREFIX', ''), 'lib')

    bl = BetterLaunch()
    ensure_router(bl)
    if world == 'empty':
        world_file = 'empty.sdf'
    else:
        world_file = bl.find('robot_simulator', f'{world}.sdf', subdir='worlds')
    include(
        arm.bringup_package, 'link6_sim.launch.py',
        gripper=gripper,
        gui='false',
        gz_args=f'-s -r -v 2 {world_file}',
        spawn_x=str(spawn_x),
        spawn_y=str(spawn_y),
    )
    person_pose = PERSON_SPAWN_POSES.get(world, {
        'x': spawn_x + PERSON_AHEAD_M,
        'y': spawn_y,
    })
    spawn_model(
        'person',
        bl.find('robot_simulator', 'model.sdf', subdir='models/person'), 'file',
        spawn_args=get_gazebo_axes_args(**person_pose))
    if mode == 'drag':
        threading.Thread(target=activate_drag_mode, daemon=True).start()
    if mode == 'moveit':
        include(
            'robot_manipulation', 'kinova_link6_moveit.launch.py',
            moveit_package=arm.moveit_package,
            motions_file=bl.find('robot_machines', 'motions.yaml', subdir=robot),
            use_sim_time=True,
            rviz=not headless,
        )
    if not headless:
        camera = (spawn_x + CAMERA_OFFSET[0], spawn_y + CAMERA_OFFSET[1],
                  *CAMERA_OFFSET[2:])
        bl.process(
            ['gz', 'sim', '-g', '--gui-config', gui_config_with_camera(bl, camera)],
            name='gazebo_gui',
        )
        threading.Thread(
            target=calm_view_control_sensitivity, daemon=True).start()
        if mode != 'moveit':
            bl.process(
                ['rviz2', '-d', bl.find(arm.control_package, 'link6_config.rviz'),
                 '--ros-args', '-p', 'use_sim_time:=true'],
                name='rviz',
            )
