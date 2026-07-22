#!/usr/bin/env python3

import argparse
import os

from robot_config.sensors.sensors import Camera
from robot_generator_common.launch.generator import LaunchGenerator


DEFAULT_OUTPUT_PATH = os.path.normpath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '..', '..', '..',
    'bringup', 'launch', 'generated'))

LAUNCH_TEMPLATE = """from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='orbbec_camera',
            executable='orbbec_camera_node',
            name='camera',
            namespace={namespace!r},
            parameters=[{parameters!r}],
        ),
    ])
"""


class SensorLaunchGenerator(LaunchGenerator):
    def generate(self) -> None:
        for camera in self.robot_config.sensors.get_all_cameras():
            if camera.SENSOR_MODEL != Camera.ORBBEC_GEMINI_335L:
                continue
            if not camera.get_launch_enabled():
                continue
            name = camera.get_name()
            parameters = dict(camera.get_ros_parameters().get(name, {}))
            parameters['camera_name'] = name
            if self.namespace in ('', '/'):
                namespace = f'sensors/{name}'
            else:
                namespace = f'{self.namespace}/sensors/{name}'
            launch_path = os.path.join(self.output_path, f'{name}.launch.py')
            with open(launch_path, 'w') as launch_file:
                launch_file.write(LAUNCH_TEMPLATE.format(
                    namespace=namespace, parameters=parameters))
            print(f'Generated launch file: {launch_path}')


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
    generator = SensorLaunchGenerator(setup_path, output_path)
    generator.generate()


if __name__ == '__main__':
    main()
