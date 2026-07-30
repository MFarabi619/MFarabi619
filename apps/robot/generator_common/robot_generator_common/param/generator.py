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

from robot_config.sensors.definitions.camera import OrbbecGemini335L
from robot_generator_common.common import BaseGenerator, ParamFile, robot_names, ROBOTS_PATH
from robot_generator_common.param.writer import ParamWriter


OUTPUT_ROOT = os.path.join('apps', 'robot', 'bringup', 'config', 'generated')


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
