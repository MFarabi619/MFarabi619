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

from ament_index_python.packages import get_package_share_directory
from better_launch import BetterLaunch, launch_this
from better_launch.convenience import read_robot_description, robot_state_publisher
from better_launch.gazebo import get_gazebo_axes_args, spawn_model


@launch_this(use_sim_time=True)
def robot_spawn(robot: str = 'robot0', x: float = -14.0, y: float = -19.0,
                z: float = 0.8, yaw: float = 0.0):
    bl = BetterLaunch()
    robot_description = read_robot_description(
        'robot_description/share', 'robot.sim.urdf', subdir=f'urdf/{robot}')
    control_config_path = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'control.yaml')
    drivetrain_config_path = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'drivetrain.generated.yaml')
    robot_description = robot_description.replace(
        'package://robot_control/config/control.yaml', control_config_path)

    robot_state_publisher(
        robot_description,
        node_name='robot_state_publisher',
        anonymous=False,
    )
    spawn_model('robot', 'robot_description', 'topic',
                spawn_args=get_gazebo_axes_args(x=x, y=y, z=z, yaw=yaw))

    def shutdown_if_spawner_failed():
        if spawner._process.returncode != 0 and not bl.is_shutdown:
            bl.shutdown('controller spawn failed, refusing to run an undrivable sim')

    spawner = bl.node(
        package='controller_manager',
        executable='spawner',
        name='controller_spawner',
        cmd_args=['joint_state_broadcaster', 'diff_drive_controller',
                  '--param-file', control_config_path,
                  '--param-file', drivetrain_config_path,
                  '--controller-manager-timeout', '60',
                  '--controller-ros-args',
                  '-r ~/cmd_vel:=/platform/cmd_vel -r ~/reference:=/platform/cmd_vel'],
        env={'ROS_SUPER_CLIENT': 'True'},
        on_exit=shutdown_if_spawner_failed)
    bl.include('robot_gz', f'{robot}_gz_bridges.launch.py', subdir=f'launch/generated/{robot}')
