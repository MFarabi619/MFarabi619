#!/usr/bin/env python3

import os

from robot_config.sensors.types.camera import OrbbecGemini335L
from robot_generator_common.common import ROBOTS_PATH, BaseGenerator, ParamFile, robot_names
from robot_generator_common.param.writer import ParamWriter


OUTPUT_ROOT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '..', '..', '..',
    'bringup', 'config', 'generated'))


class ParamGenerator(BaseGenerator):
    def __init__(self, setup_path: str, output_path: str) -> None:
        super().__init__(setup_path)
        self.output_path = output_path
        os.makedirs(self.output_path, exist_ok=True)

    def generate(self) -> None:
        self.generate_sensors()

    def generate_sensors(self) -> None:
        for sensor in self.robot_config.sensors.get_all_sensors():
            if not sensor.get_launch_enabled():
                continue
            if isinstance(sensor, OrbbecGemini335L):
                continue
            ros_parameters = sensor.get_ros_parameters()
            for node in ros_parameters:
                param_file = ParamFile(
                    name=node,
                    namespace=self.namespace,
                    path=self.output_path,
                    parameters={node: ros_parameters[node]})
                param_writer = ParamWriter(param_file)
                param_writer.write_file()
                print(f'Generated config: {param_file.full_path}')


def main():
    for robot_name in robot_names():
        ParamGenerator(
            os.path.join(ROBOTS_PATH, robot_name),
            os.path.join(OUTPUT_ROOT, robot_name)).generate()


if __name__ == '__main__':
    main()
