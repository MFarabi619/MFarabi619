#!/usr/bin/env python3

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

from robot_generator_common.common import LaunchFile, robot_names, ROBOTS_PATH
from robot_generator_common.launch.generator import LaunchGenerator
from robot_generator_common.launch.writer import LaunchWriter


OUTPUT_ROOT = os.path.join('apps', 'robot', 'simulator', 'gz', 'launch', 'generated')


class GzLaunchGenerator(LaunchGenerator):
    GZ_TO_ROS_CLOCK = '@rosgraph_msgs/msg/Clock[gz.msgs.Clock'
    GZ_TO_ROS_TWIST = '@geometry_msgs/msg/Twist[gz.msgs.Twist'
    ROS_TO_GZ_TWIST = '@geometry_msgs/msg/Twist]gz.msgs.Twist'
    GZ_TO_ROS_CAMERA_INFO = '@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'
    GZ_TO_ROS_NAVSATFIX = '@sensor_msgs/msg/NavSatFix[gz.msgs.NavSat'

    def __init__(self, setup_path: str, output_path: str) -> None:
        super().__init__(setup_path, output_path)

        if self.namespace in ('', '/'):
            self.robot_name = self.robot_config.get_platform_model()
        else:
            self.robot_name = self.namespace + '/' + self.robot_config.get_platform_model()

        robot_dir = os.path.basename(output_path)
        self.gz_bridges_launch_file = LaunchFile(
            name=f'{robot_dir}_gz_bridges',
            path=self.output_path)

        # clock bridge
        self.clock_node = LaunchFile.Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            name='clock_bridge',
            namespace=self.namespace,
            arguments=[
                '/clock' + self.GZ_TO_ROS_CLOCK
            ])

        cameras = self.robot_config.sensors.get_all_cameras()

        self.image_bridge_node = LaunchFile.Node(
            package='ros_gz_image',
            executable='image_bridge',
            name='image_bridge',
            namespace=self.namespace,
            parameters=[{
                f'sensors.{camera.get_name()}.color.image.enable_pub_plugins':
                    ['image_transport/compressed']
                for camera in cameras
            }],
            arguments=[
                f'sensors/{camera.get_name()}/color/image'
                for camera in cameras
            ])

        # camera_info + gps via parameter_bridge
        camera_info_bridges = [
            f'/sensors/{camera.get_name()}/color/camera_info' + self.GZ_TO_ROS_CAMERA_INFO
            for camera in cameras
        ]
        self.sensors_bridge_node = LaunchFile.Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            name='sensors_bridge',
            namespace=self.namespace,
            arguments=camera_info_bridges + [
                '/sensors/gps_0/fix' + self.GZ_TO_ROS_NAVSATFIX
            ])

        self.bridge_components = [
            self.clock_node,
            self.image_bridge_node,
            self.sensors_bridge_node,
        ]

    def generate(self) -> None:
        gz_bridges_launch_writer = LaunchWriter(self.gz_bridges_launch_file)

        for component in self.bridge_components:
            gz_bridges_launch_writer.add(component)

        gz_bridges_launch_writer.generate_file()


def main():
    for robot_name in robot_names():
        GzLaunchGenerator(
            os.path.join(ROBOTS_PATH, robot_name),
            os.path.join(OUTPUT_ROOT, robot_name)).generate()


if __name__ == '__main__':
    main()
