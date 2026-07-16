#!/usr/bin/env python3

import argparse
import os

from robot_generator_common.common import BaseGenerator


DEFAULT_OUTPUT_PATH = os.path.normpath(os.path.join(
    os.path.dirname(__file__), '..', '..', '..',
    'robot_bringup', 'launch', 'generated'))


class LaunchGenerator(BaseGenerator):
    def __init__(self,
                 setup_path: str = None,
                 output_path: str = DEFAULT_OUTPUT_PATH) -> None:
        super().__init__(setup_path)
        self.launch_path = output_path
        os.makedirs(self.launch_path, exist_ok=True)

    def generate(self) -> None:
        raise NotImplementedError()


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
    generator = LaunchGenerator(setup_path, output_path)
    generator.generate()


if __name__ == '__main__':
    main()
