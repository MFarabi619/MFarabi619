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

from robot_generator_common.common import LaunchFile, Package


class LaunchWriter():
    INDENT_UNIT = '    '
    LICENSE_HEADER = (
        'Copyright 2026 Mumtahin Farabi',
        '',
        'This program is free software: you can redistribute it and/or modify',
        'it under the terms of the GNU General Public License as published by',
        'the Free Software Foundation, either version 3 of the License, or',
        '(at your option) any later version.',
        '',
        'This program is distributed in the hope that it will be useful,',
        'but WITHOUT ANY WARRANTY; without even the implied warranty of',
        'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the',
        'GNU General Public License for more details.',
        '',
        'You should have received a copy of the GNU General Public License',
        'along with this program.  If not, see <https://www.gnu.org/licenses/>.',
    )

    def __init__(self, launch_file: LaunchFile):
        self.launch_file = launch_file
        self.actions: List[str] = []
        self.included_packages: List[Package] = []
        self.included_launch_files: List[LaunchFile] = []
        self.nodes: List[LaunchFile.Node] = []
        self.declared_launch_args: List[LaunchFile.LaunchArg] = []
        self.processes: List[LaunchFile.Process] = []
        self.lines: List[str] = []
        os.makedirs(os.path.dirname(self.launch_file.get_full_path()), exist_ok=True)
        self.file = open(self.launch_file.get_full_path(), 'w+')

    def write(self, line, indent_level=1):
        self.lines.append('{0}{1}'.format(self.INDENT_UNIT * indent_level, line))

    def write_comment(self, comment, indent_level=1):
        self.write('# {0}'.format(comment), indent_level)

    def write_newline(self):
        self.write('', 0)

    def write_string(self, string: str, indent_level=1, prefix='', suffix=''):
        self.write("{0}'{1}'{2}".format(prefix, string, suffix), indent_level)

    def write_scalar(self, value, indent_level=1, prefix='', suffix=''):
        self.write('{0}{1}{2}'.format(prefix, value, suffix), indent_level)

    def write_variable(self, variable: LaunchFile.Variable, indent_level=1, prefix='', suffix=''):
        self.write('{0}{1}{2}'.format(prefix, variable.name, suffix), indent_level)

    def write_value(self, value: object, indent_level=1, prefix='', suffix=''):
        if isinstance(value, str):
            self.write_string(value, indent_level, prefix, suffix)
        elif isinstance(value, bool):
            self.write_scalar(value, indent_level, prefix, suffix)
        elif isinstance(value, int):
            self.write_scalar(value, indent_level, prefix, suffix)
        elif isinstance(value, LaunchFile.Variable):
            self.write_variable(value, indent_level, prefix, suffix)
        elif isinstance(value, dict):
            self.write_dictionary(value, indent_level, prefix, suffix)
        elif isinstance(value, list):
            self.write_list(value, indent_level, prefix, suffix)
        elif isinstance(value, tuple):
            self.write_tuple(value, indent_level, prefix, suffix)

    def write_dictionary(self, dictionary: dict, indent_level=1, prefix='', suffix=''):
        self.write('{0}{{'.format(prefix), indent_level)
        for key, value in dictionary.items():
            self.write_value(
                value, indent_level + 1, prefix="'{0}': ".format(key), suffix=',')
        self.write('}}{0}'.format(suffix), indent_level)

    def write_list(self, values: list, indent_level=1, prefix='', suffix=''):
        self.write('{0}['.format(prefix), indent_level)
        for value in values:
            self.write_value(value, indent_level + 1, suffix=',')
        self.write(']{0}'.format(suffix), indent_level)

    def write_tuple(self, pair: tuple, indent_level=1, prefix='', suffix=''):
        self.write('{0}('.format(prefix), indent_level)
        self.write_value(pair[0], indent_level + 1, suffix=',')
        self.write_value(pair[1], indent_level + 1, suffix=',')
        self.write('){0}'.format(suffix), indent_level)

    def find_package(self, package: Package):
        if package not in self.included_packages:
            self.included_packages.append(package)

    def add_launch_arg(self, launch_arg: LaunchFile.LaunchArg):
        if launch_arg not in self.declared_launch_args:
            # Add launch arg to launch description actions
            self.actions.append(launch_arg.declaration)
            self.declared_launch_args.append(launch_arg)

    def add_launch_file(self, launch_file: LaunchFile):
        if launch_file not in self.included_launch_files:
            self.included_launch_files.append(launch_file)

    def add_node(self, node: LaunchFile.Node):
        if node not in self.nodes:
            self.nodes.append(node)

    def add_process(self, process: LaunchFile.Process):
        if process not in self.processes:
            self.processes.append(process)

    def add(self, component: LaunchFile | LaunchFile.LaunchComponent):
        if isinstance(component, LaunchFile.LaunchArg):
            self.add_launch_arg(component)
        elif isinstance(component, LaunchFile):
            self.add_launch_file(component)
        elif isinstance(component, LaunchFile.Node):
            self.add_node(component)
        elif isinstance(component, LaunchFile.Process):
            self.add_process(component)

    def get_function_name(self):
        base = os.path.basename(self.launch_file.get_full_path())
        return base.replace('.launch.py', '').replace('.', '_')

    def initialize_file(self):
        for line in self.LICENSE_HEADER:
            self.write('# {0}'.format(line) if line else '#', 0)
        self.write_newline()
        self.write_newline()
        self.write('from better_launch import BetterLaunch, launch_this', 0)
        self.write_newline()
        self.write_newline()
        self.write('@launch_this', 0)
        if len(self.declared_launch_args) > 0:
            params = ', '.join(
                "{0}: str = '{1}'".format(arg.name, arg.default_value)
                for arg in self.declared_launch_args)
            self.write('def {0}({1}):'.format(self.get_function_name(), params), 0)
        else:
            self.write('def {0}():'.format(self.get_function_name()), 0)
        self.write('bl = BetterLaunch()')

    def close_file(self):
        self.file.write('\n'.join(self.lines).rstrip('\n') + '\n')
        self.file.close()

    def write_node(self, node: LaunchFile.Node):
        self.write('bl.node(')
        self.write("package='{0}',".format(node.package), indent_level=2)
        self.write("executable='{0}',".format(node.executable), indent_level=2)
        self.write("name='{0}',".format(node.name), indent_level=2)
        if node.namespace:
            self.write("namespace='{0}',".format(node.namespace), indent_level=2)
        if len(node.arguments) > 0:
            self.write_value(node.arguments, indent_level=2, prefix='cmd_args=', suffix=',')
        if len(node.remappings) > 0:
            remaps = dict(node.remappings)
            self.write_value(remaps, indent_level=2, prefix='remaps=', suffix=',')
        merged = {}
        for entry in node.parameters:
            if isinstance(entry, dict):
                merged.update(entry)
        use_sim_time = merged.pop('use_sim_time', None)
        if use_sim_time is not None:
            self.write('use_sim_time={0},'.format(use_sim_time), indent_level=2)
        if len(merged) > 0:
            self.write_value(merged, indent_level=2, prefix='params=', suffix=',')
        self.write(')')

    def write_process(self, process: LaunchFile.Process):
        name = process.name.replace('process_', '')
        if isinstance(process.cmd, str):
            self.write("bl.process('{0}', name='{1}')".format(process.cmd, name))
        else:
            self.write('bl.process(')
            self.write_value(process.cmd, indent_level=2, suffix=',')
            self.write("name='{0}',".format(name), indent_level=2)
            self.write(')')

    def generate_file(self):
        self.initialize_file()

        if len(self.included_launch_files) > 0:
            self.write_newline()
            for launch_file in self.included_launch_files:
                package = launch_file.package.name if launch_file.package else None
                self.write("bl.include('{0}', '{1}')".format(package, launch_file.file))

        for node in self.nodes:
            self.write_newline()
            self.write_node(node)

        for process in self.processes:
            self.write_newline()
            self.write_process(process)

        self.close_file()
        print('Generated launch file: {0}'.format(self.launch_file.get_full_path()))
