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


from better_launch.convenience import read_robot_description, robot_state_publisher
from better_launch.gazebo import get_gazebo_axes_args, spawn_model
from robot_boot.drivetrain_parameters import (
    CONTROLLER_MANAGER_TIMEOUT_SECONDS, write_drivetrain_parameters_file)
from robot_boot.urdf import wheel_geometry
from robot_simulation.gz_bridges import spawn_simulation_bridges


def spawn_robot(bl, machine, world, x, y, z, yaw, depth_scan_enabled=False):
    robot = machine.name
    urdf_path = bl.find('robot_description', 'robot.sim.urdf', subdir=f'urdf/{robot}')
    robot_description = read_robot_description(
        'robot_description/share', 'robot.sim.urdf', subdir=f'urdf/{robot}')
    control_parameters_file = bl.find('robot_control', 'control.yaml')
    drivetrain = machine.platform.drivetrain
    drivetrain_parameters_file = write_drivetrain_parameters_file(
        *wheel_geometry(urdf_path), drivetrain.motion_limits(drivetrain.model))
    robot_description = robot_description.replace(
        'package://robot_control/config/control.yaml', control_parameters_file)

    # Absolute '/robot_description' escaped the per-robot group, so every robot
    # published its urdf to one topic and each spawn raced for whichever landed
    # last — two robots, one description.
    robot_state_publisher(
        robot_description,
        node_name='robot_state_publisher',
        anonymous=False,
    )
    spawn_model(robot, f'/{robot}/robot_description', 'topic',
                spawn_args=get_gazebo_axes_args(x=x, y=y, z=z, yaw=yaw))

    spawner = None

    def shutdown_if_spawner_failed():
        if spawner is None:
            return
        if spawner.join() != 0 and not bl.is_shutdown:
            bl.shutdown('controller spawn failed, refusing to run an undrivable sim')

    spawner = bl.node(
        package='controller_manager',
        executable='spawner',
        name='controller_spawner',
        cmd_args=['joint_state_broadcaster', 'diff_drive_controller',
                  '--param-file', control_parameters_file,
                  '--param-file', drivetrain_parameters_file,
                  '--controller-manager-timeout', CONTROLLER_MANAGER_TIMEOUT_SECONDS,
                  '--controller-ros-args',
                  '-r ~/cmd_vel:=platform/cmd_vel -r ~/reference:=platform/cmd_vel'],
        env={'ROS_SUPER_CLIENT': 'True'},
        on_exit=shutdown_if_spawner_failed)

    spawn_simulation_bridges(bl, machine, world, robot, depth_scan_enabled)
