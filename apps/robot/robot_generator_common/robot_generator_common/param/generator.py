#!/usr/bin/env python3

import argparse
import os

from robot_generator_common.common import BaseGenerator, ParamFile
from robot_generator_common.param.writer import ParamWriter


DEFAULT_OUTPUT_PATH = os.path.normpath(os.path.join(
    os.path.dirname(__file__), '..', '..', '..',
    'robot_bringup', 'config', 'generated'))


class ParamGenerator(BaseGenerator):
    def __init__(self,
                 setup_path: str = None,
                 output_path: str = DEFAULT_OUTPUT_PATH) -> None:
        super().__init__(setup_path)
        self.params_path = output_path
        os.makedirs(self.params_path, exist_ok=True)

    def generate(self) -> None:
        self.generate_sensors()

    def generate_sensors(self) -> None:
        for sensor in self.robot_config.sensors.get_all_sensors():
            ros_parameters = sensor.get_ros_parameters()
            for node in ros_parameters:
                param_file = ParamFile(
                    name=node,
                    namespace=self.namespace,
                    path=self.params_path,
                    parameters={node: ros_parameters[node]})
                param_writer = ParamWriter(param_file)
                param_writer.write_file()
                print(f'Generated config: {param_file.full_path}')


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
        help='Output directory for the generated parameter files.',
    )
    args = parser.parse_args()
    return args.setup_path, args.output_path


def main():
    setup_path, output_path = get_args()
    generator = ParamGenerator(setup_path, output_path)
    generator.generate()


if __name__ == '__main__':
    main()
