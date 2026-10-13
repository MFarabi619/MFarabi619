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
import subprocess
import threading
import time

import yaml

from better_launch import BetterLaunch, launch_this

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


@launch_this(use_sim_time=True)
def arm_simulation(robot: str = 'kinova-link-6', gripper: str = '',
                   headless: bool = False, mode: str = 'drag'):
    headless = str(headless).lower() in ('true', '1')
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        arm = yaml.safe_load(machine_file)['arm']
    gripper = gripper or arm['gripper']
    install_arm = os.path.abspath('install-arm')
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)
    os.environ['GZ_SIM_RESOURCE_PATH'] = ':'.join(filter(None, [
        os.environ.get('GZ_SIM_RESOURCE_PATH', ''),
        os.path.join(install_arm, 'share')]))
    os.environ['GZ_SIM_SYSTEM_PLUGIN_PATH'] = os.path.join(
        os.environ.get('CONDA_PREFIX', ''), 'lib')

    bl = BetterLaunch()
    bl.process(
        os.path.join(
            os.environ['CONDA_PREFIX'], 'lib', 'rmw_zenoh_cpp', 'rmw_zenohd'),
        name='zenoh_router',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.include(
        arm['bringup_package'], 'link6_sim.launch.py',
        pass_launch_func_args=False,
        gripper=gripper,
        gui='false',
        gz_args='-s -r -v 2 empty.sdf',
    )
    if mode == 'drag':
        threading.Thread(target=activate_drag_mode, daemon=True).start()
    if mode == 'moveit':
        bl.include(
            arm['moveit_package'], 'move_group.launch.py',
            pass_launch_func_args=False,
            use_sim_time='true',
        )
        rviz_config = os.path.abspath('manipulation/config/moveit.rviz')
    else:
        rviz_config = os.path.join(
            install_arm, 'share', arm['control_package'], 'config',
            'link6_config.rviz')
    if not headless:
        bl.process(
            'gz sim -g --force-version 8 --gui-config '
            + os.path.abspath('simulation/arm_gui.config'),
            name='gazebo_gui',
        )
        threading.Thread(
            target=calm_view_control_sensitivity, daemon=True).start()
        bl.process(
            f'rviz2 -d {rviz_config} --ros-args -p use_sim_time:=true',
            name='rviz',
        )
