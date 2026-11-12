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
from better_launch.convenience import read_robot_description, robot_state_publisher
from robot_boot.launch_policy import RESPAWN, include
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def kinova_link6(
    description_package: str = 'link6_description',
    moveit_package: str = 'link6_moveit_config',
    moveit_robot_name: str = 'link6',
    gripper: str = 'robotiq_2f_85',
    robot_password: str = 'admin',
    motions_file: str = '',
    rviz_enabled: bool = False,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.process(
        [bl.find('robot_manipulation', 'kinova_link6_bridge'), '--robot-password', robot_password],
        name='kinova_link6_bridge',
        **RESPAWN,
    )
    robot_state_publisher(read_robot_description(
        description_package, f'{moveit_robot_name}.urdf.xacro',
        xacro_args=[f'gripper:={gripper}']))
    bl.node(
        package='robot_manipulation',
        executable='kinova_link6_bridge_node',
        remaps={'arm_teleop/cmd_vel': 'joy_teleop/cmd_vel'},
    )
    include(
        'robot_manipulation', 'kinova_link6_moveit.launch.py',
        moveit_package=moveit_package,
        motions_file=motions_file,
        rviz_enabled=rviz_enabled,
    )
