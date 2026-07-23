#!/usr/bin/env python3

import os

from robot_config.sensors.sensors import Camera
from robot_generator_common.common import ROBOTS_PATH, robot_names
from robot_generator_common.launch.generator import LaunchGenerator


OUTPUT_ROOT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '..',
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
            parameters['color.image_raw.enable_pub_plugins'] = [
                'image_transport/compressed']
            if self.namespace in ('', '/'):
                namespace = f'sensors/{name}'
            else:
                namespace = f'{self.namespace}/sensors/{name}'
            launch_path = os.path.join(self.output_path, f'{name}.launch.py')
            with open(launch_path, 'w') as launch_file:
                launch_file.write(LAUNCH_TEMPLATE.format(
                    namespace=namespace, parameters=parameters))
            print(f'Generated launch file: {launch_path}')


def main():
    for robot_name in robot_names():
        SensorLaunchGenerator(
            os.path.join(ROBOTS_PATH, robot_name),
            os.path.join(OUTPUT_ROOT, robot_name)).generate()


if __name__ == '__main__':
    main()
