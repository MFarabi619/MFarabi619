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
from robot_boot.arm_description import write_urdf_file_with_arms
from robot_boot.zenoh_router import ensure_zenoh_router
from robot_machines.machine import load_machine


# Not urdf_launch's display.launch.py: it runs every URDF through xacro, whose banner pushes our
# <?xml-model?> line below the top, where urdfdom refuses to parse it.
@launch_this
def rviz(robot: str = 'taro'):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    urdf_path = write_urdf_file_with_arms(
        bl.find('robot_description', 'robot.urdf', subdir=f'urdf/{robot}'),
        load_machine(robot).manipulators.arms, 'hardware')
    robot_state_publisher(
        read_robot_description(None, urdf_path),
        node_name='robot_state_publisher',
        anonymous=False,
    )
    bl.node(
        package='joint_state_publisher_gui',
        executable='joint_state_publisher_gui',
        name='joint_state_publisher_gui',
    )
    bl.process(['rviz2', '-d', bl.find('urdf_launch', 'urdf.rviz')], name='rviz')
