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
import tempfile
import xml.etree.ElementTree as ElementTree

from ament_index_python.packages import get_package_share_directory
from better_launch.convenience import read_robot_description, robot_state_publisher
import yaml
from better_launch.gazebo import get_gazebo_axes_args, spawn_model
from gz_bridges import spawn_sim_bridges


def wheel_geometry(robot_description):
    robot = ElementTree.fromstring(robot_description)
    joint_by_child = {}
    for joint in robot.iter('joint'):
        parent = joint.find('parent')
        if parent is None:
            continue
        origin = joint.find('origin')
        xyz = origin.get('xyz', '0 0 0') if origin is not None else '0 0 0'
        rpy = origin.get('rpy', '0 0 0') if origin is not None else '0 0 0'
        joint_by_child[joint.find('child').get('link')] = (
            parent.get('link'), float(xyz.split()[1]),
            any(float(angle) != 0.0 for angle in rpy.split()), joint.get('name'))

    def lateral_offset(link):
        offset = 0.0
        while link in joint_by_child:
            link, y, is_rotated, joint_name = joint_by_child[link]
            if is_rotated:
                raise RuntimeError(
                    f'{joint_name} has a rotated origin;'
                    ' wheel_geometry only handles pure-translation wheel chains')
            offset += y
        return offset

    wheel_separation = abs(
        lateral_offset('rear_left_wheel_link')
        - lateral_offset('rear_right_wheel_link'))
    radii = {
        float(cylinder.get('radius'))
        for link in robot.iter('link')
        if link.get('name').endswith('_wheel_link')
        for cylinder in link.find('collision').iter('cylinder')
    }
    if len(radii) != 1:
        raise RuntimeError(f'expected one wheel collision radius, found {radii}')
    return wheel_separation, radii.pop()


def write_drivetrain_parameters(wheel_separation, wheel_radius):
    parameters = {
        '/**/diff_drive_controller': {
            'ros__parameters': {
                'wheel_separation': wheel_separation,
                'wheel_radius': wheel_radius,
            },
        },
    }
    parameters_file = tempfile.NamedTemporaryFile(
        mode='w', prefix='drivetrain_', suffix='.yaml', delete=False)
    yaml.safe_dump(parameters, parameters_file)
    parameters_file.close()
    return parameters_file.name


def spawn_robot(bl, robot, world, x, y, z, yaw, depth_scan=False):
    robot_description = read_robot_description(
        'robot_description/share', 'robot.sim.urdf', subdir=f'urdf/{robot}')
    control_config_path = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'control.yaml')
    drivetrain_parameters_path = write_drivetrain_parameters(
        *wheel_geometry(robot_description))
    robot_description = robot_description.replace(
        'package://robot_control/config/control.yaml', control_config_path)

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

    def shutdown_if_spawner_failed():
        if spawner._process.returncode != 0 and not bl.is_shutdown:
            bl.shutdown('controller spawn failed, refusing to run an undrivable sim')

    spawner = bl.node(
        package='controller_manager',
        executable='spawner',
        name='controller_spawner',
        cmd_args=['joint_state_broadcaster', 'diff_drive_controller',
                  '--param-file', control_config_path,
                  '--param-file', drivetrain_parameters_path,
                  '--controller-manager-timeout', '60',
                  '--controller-ros-args',
                  '-r ~/cmd_vel:=platform/cmd_vel -r ~/reference:=platform/cmd_vel'],
        env={'ROS_SUPER_CLIENT': 'True'},
        on_exit=shutdown_if_spawner_failed)

    spawn_sim_bridges(bl, robot, world, robot, depth_scan)
