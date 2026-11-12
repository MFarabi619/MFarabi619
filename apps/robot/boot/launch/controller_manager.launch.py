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


from better_launch import BetterLaunch, launch_this
from robot_boot.drivetrain_parameters import (
    CONTROLLER_MANAGER_TIMEOUT_SECONDS, write_drivetrain_parameters_file)
from robot_boot.launch_policy import RESPAWN
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def controller_manager(
    wheel_separation: float = 0.0,
    wheel_radius: float = 0.0,
    params_file: str = '',
    max_linear_velocity_meters_per_second: float = 0.0,
    max_angular_velocity_radians_per_second: float = 0.0,
    max_linear_acceleration_meters_per_second_squared: float = 0.0,
    max_linear_jerk_meters_per_second_cubed: float = 0.0,
    max_angular_acceleration_radians_per_second_squared: float = 0.0,
    max_angular_jerk_radians_per_second_cubed: float = 0.0,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    params_file = params_file or bl.find('robot_control', 'control.yaml')
    drivetrain_parameters_file = write_drivetrain_parameters_file(
        wheel_separation, wheel_radius, {
            'max_linear_velocity_meters_per_second': max_linear_velocity_meters_per_second,
            'max_angular_velocity_radians_per_second': max_angular_velocity_radians_per_second,
            'max_linear_acceleration_meters_per_second_squared':
                max_linear_acceleration_meters_per_second_squared,
            'max_linear_jerk_meters_per_second_cubed': max_linear_jerk_meters_per_second_cubed,
            'max_angular_acceleration_radians_per_second_squared':
                max_angular_acceleration_radians_per_second_squared,
            'max_angular_jerk_radians_per_second_cubed': max_angular_jerk_radians_per_second_cubed,
        })

    def spawn_controllers():
        if bl.is_shutdown:
            return
        bl.node(
            package='controller_manager',
            executable='spawner',
            name='controller_spawner',
            cmd_args=[
                'joint_state_broadcaster', 'diff_drive_controller',
                '--param-file', params_file,
                '--param-file', drivetrain_parameters_file,
                '--controller-manager-timeout', CONTROLLER_MANAGER_TIMEOUT_SECONDS,
                '--controller-ros-args',
                '-r ~/cmd_vel:=platform/cmd_vel -r /tf:=tf -r /tf_static:=tf_static',
            ],
        )

    bl.node(
        package='controller_manager',
        executable='ros2_control_node',
        name='controller_manager',
        remaps={'~/robot_description': 'robot_description'},
        param_files=[params_file, drivetrain_parameters_file],
        remap_qualifier='controller_manager',
        **RESPAWN,
        on_exit=spawn_controllers,
    )
    spawn_controllers()
