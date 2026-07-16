#!/usr/bin/env python3

import argparse
import os

from robot_generator_common.common import LaunchFile
from robot_generator_common.launch.generator import LaunchGenerator
from robot_generator_common.launch.writer import LaunchWriter


DEFAULT_OUTPUT_PATH = os.path.normpath(os.path.join(
    os.path.dirname(__file__), '..', '..', '..',
    'robot_gz', 'launch', 'generated'))


class GzLaunchGenerator(LaunchGenerator):
    GZ_TO_ROS_CLOCK = '@rosgraph_msgs/msg/Clock[gz.msgs.Clock'
    GZ_TO_ROS_TWIST = '@geometry_msgs/msg/Twist[gz.msgs.Twist'
    ROS_TO_GZ_TWIST = '@geometry_msgs/msg/Twist]gz.msgs.Twist'
    GZ_TO_ROS_CAMERA_INFO = '@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'
    GZ_TO_ROS_NAVSAT = '@sensor_msgs/msg/NavSatFix[gz.msgs.NavSat'

    def __init__(self,
                 setup_path: str = None,
                 output_path: str = DEFAULT_OUTPUT_PATH) -> None:
        super().__init__(setup_path, output_path)

        if self.namespace in ('', '/'):
            self.robot_name = self.robot_config.get_platform_model()
        else:
            self.robot_name = self.namespace + '/' + self.robot_config.get_platform_model()

        self.gz_bridges_launch_file = LaunchFile(
            name='robot_gz_bridges',
            path=self.launch_path)

        # clock bridge
        self.clock_node = LaunchFile.Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            name='clock_bridge',
            namespace=self.namespace,
            arguments=[
                '/clock' + self.GZ_TO_ROS_CLOCK
            ])

        # camera images via ros_gz_image (also republishes .../compressed)
        self.image_bridge_node = LaunchFile.Node(
            package='ros_gz_image',
            executable='image_bridge',
            name='image_bridge',
            namespace=self.namespace,
            arguments=[
                'camera/image_raw'
            ])

        # camera_info + gps via parameter_bridge
        self.sensors_bridge_node = LaunchFile.Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            name='sensors_bridge',
            namespace=self.namespace,
            arguments=[
                '/camera/camera_info' + self.GZ_TO_ROS_CAMERA_INFO,
                '/gps/fix' + self.GZ_TO_ROS_NAVSAT
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


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-s',
        '--setup-path',
        type=str,
        action='store',
        dest='setup_path',
        default=None,
        help='Setup path, i.e. the directory containing robot.yaml.',
    )
    parser.add_argument(
        '-o',
        '--output-path',
        type=str,
        action='store',
        dest='output_path',
        default=DEFAULT_OUTPUT_PATH,
        help='Output directory for the generated launch files.',
    )
    args = parser.parse_args()
    return args.setup_path, args.output_path


def main():
    setup_path, output_path = get_args()
    generator = GzLaunchGenerator(setup_path, output_path)
    generator.generate()


if __name__ == '__main__':
    main()
