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

from typing import List

from ament_index_python.packages import get_package_share_directory

from robot_config.common.utils.yaml import read_yaml
from robot_config.robot_config import RobotConfig


ROBOTS_PATH = os.path.join('config', 'robots')


def robot_names():
    return sorted(
        name for name in os.listdir(ROBOTS_PATH)
        if os.path.isfile(os.path.join(ROBOTS_PATH, name, 'robot.yaml')))


class Package():

    def __init__(self,
                 name: str
                 ) -> None:
        self.name = name
        self.declaration = 'pkg_' + name

    def get_name(self) -> str:
        return self.name

    def find_package_share(self) -> str:
        return "{0} = FindPackageShare('{1}')".format(self.declaration, self.name)


class LaunchFile():
    class LaunchComponent():

        def __init__(self, name: str) -> None:
            self.name = name

    class Process(LaunchComponent):

        def __init__(self,
                     name: str,
                     cmd: List[list] | List[str]) -> None:
            super().__init__(name)
            self.declaration = 'process_' + self.name
            self.cmd = cmd

    class LaunchArg(LaunchComponent):

        def __init__(self, name: str, default_value: str = '', description: str = '') -> None:
            super().__init__(name)
            self.default_value = default_value
            self.description = description
            self.declaration = 'launch_arg_' + self.name

    class Variable(LaunchComponent):

        def __init__(self, name: str) -> None:
            super().__init__(name)

    class Node(LaunchComponent):

        def __init__(self,
                     name: str,
                     package: str,
                     executable: str,
                     namespace: str = '',
                     parameters: List[dict] | List[str] = [],
                     arguments: List[list] | List[str] = [],
                     remappings: List[tuple] = []) -> None:
            super().__init__(name)
            self.declaration = 'node_' + self.name
            self.package = package
            self.executable = executable
            self.namespace = namespace
            self.parameters = parameters
            self.arguments = arguments
            self.remappings = remappings

    @staticmethod
    def get_static_tf_node(name: str,
                           namespace: str,
                           parent_link: str,
                           child_link: str,
                           use_sim_time: bool = False) -> 'LaunchFile.Node':
        return LaunchFile.Node(
            name=name + '_static_tf',
            package='tf2_ros',
            executable='static_transform_publisher',
            namespace=namespace,
            parameters=[{'use_sim_time': use_sim_time}],
            arguments=[
                '--frame-id', parent_link,
                '--child-frame-id', child_link
            ],
            remappings=[
                ('/tf', 'tf'),
                ('/tf_static', 'tf_static'),
            ]
        )

    def __init__(self,
                 name: str,
                 path: str = 'launch',
                 package: Package | None = None,
                 args: List[tuple] | None = None,
                 filename: str | None = None,
                 ) -> None:
        self.package = package
        self.path = path
        self.name = 'launch_' + name
        self.declaration = 'launch_file_{0}'.format(name)
        if filename:
            self.file = '{0}.launch.py'.format(filename)
        else:
            self.file = '{0}.launch.py'.format(name)
        self.args = args

    def get_full_path(self):
        if self.package:
            return os.path.join(
                get_package_share_directory(self.package.name),
                self.path,
                self.file)
        else:
            return os.path.join(
                self.path,
                self.file)


class ParamFile():

    def __init__(self,
                 name: str,
                 namespace: str = '',
                 path: str = 'config',
                 parameters: dict = {}
                 ) -> None:
        self.path = path
        self.namespace = namespace
        self.name = f'param_file_{name}'
        self.file = f'{name}.yaml'
        self.parameters = {}
        self.parameters.update(parameters)

    @property
    def full_path(self) -> str:
        return os.path.join(self.path, self.file)

    def to_ros_parameters(self) -> dict:
        """Convert parameters to the ros__parameters format."""
        nodes = {}
        for node in self.parameters:
            nodes[node] = {'ros__parameters': self.parameters[node]}
        if self.namespace:
            return {self.namespace: nodes}
        return nodes


class BaseGenerator():

    def __init__(self, setup_path: str) -> None:
        self.config_path = os.path.join(setup_path, 'robot.yaml')
        self.setup_path = setup_path

        self.raw_config = read_yaml(self.config_path)
        self.robot_config = RobotConfig(self.raw_config)

        self.serial_number = self.robot_config.serial_number
        self.namespace = self.robot_config.system.namespace

    # This method should be overwritten by the child class
    def generate(self) -> None:
        raise NotImplementedError()
