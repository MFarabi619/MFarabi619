import os

from typing import List

from robot_generator_common.common import LaunchFile, Package


class LaunchWriter():
    INDENT_UNIT = '    '

    def __init__(self, launch_file: LaunchFile):
        self.launch_file = launch_file
        self.actions: List[str] = []
        self.included_packages: List[Package] = []
        self.included_launch_files: List[LaunchFile] = []
        self.nodes: List[LaunchFile.Node] = []
        self.declared_launch_args: List[LaunchFile.LaunchArg] = []
        self.processes: List[LaunchFile.Process] = []
        os.makedirs(os.path.dirname(self.launch_file.get_full_path()), exist_ok=True)
        self.file = open(self.launch_file.get_full_path(), 'w+')

    def write(self, line, indent_level=1):
        self.file.write('{0}{1}\n'.format(self.INDENT_UNIT * indent_level, line))

    def write_comment(self, comment, indent_level=1):
        self.write('# {0}'.format(comment), indent_level)

    def write_newline(self):
        self.write('', 0)

    def write_string(self, string: str, indent_level=1):
        self.write("'{0}'".format(string), indent_level)

    def write_boolean(self, boolean: bool, indent_level=1):
        self.write(boolean, indent_level)

    def write_integer(self, integer: int, indent_level=1):
        self.write(integer, indent_level)

    def write_variable(self, variable: LaunchFile.Variable, indent_level=1):
        self.write(variable.name, indent_level)

    def write_value(self, value: object, indent_level=1):
        if isinstance(value, str):
            self.write_string(value, indent_level)
        elif isinstance(value, bool):
            self.write_boolean(value, indent_level)
        elif isinstance(value, int):
            self.write_integer(value, indent_level)
        elif isinstance(value, LaunchFile.Variable):
            self.write_variable(value, indent_level)
        elif isinstance(value, dict):
            self.write_dictionary(value, indent_level)
        elif isinstance(value, list):
            self.write_list(value, indent_level)
        elif isinstance(value, tuple):
            self.write_tuple(value, indent_level)

    def write_key_value_pair(self, key: str, value, indent_level=1):
        if isinstance(value, str):
            self.write("'{0}': '{1}'".format(key, value), indent_level)
        else:
            self.write("'{0}': {1}".format(key, value), indent_level)

    def write_dictionary(self, dictionary: dict, indent_level=1):
        self.write('{', indent_level)
        for entry_key in dictionary.keys():
            self.write_key_value_pair(entry_key, dictionary[entry_key], indent_level + 1)
            self.write(',', indent_level + 1)
        self.write('}', indent_level)

    def write_list(self, values: list, indent_level=1):
        self.write('[', indent_level)
        for value in values:
            self.write_value(value, indent_level + 1)
            self.write(',', indent_level + 1)
        self.write(']', indent_level)

    def write_tuple(self, pair: tuple, indent_level=1):
        self.write('(', indent_level)
        self.write_value(pair[0], indent_level + 1)
        self.write(',', indent_level + 1)
        self.write_value(pair[1], indent_level + 1)
        self.write(')', indent_level)

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
        self.write_newline()

    def close_file(self):
        self.file.close()

    def generate_file(self):
        self.initialize_file()

        if len(self.included_launch_files) > 0:
            for launch_file in self.included_launch_files:
                package = launch_file.package.name if launch_file.package else None
                self.write("bl.include('{0}', '{1}')".format(package, launch_file.file))
            self.write_newline()

        if len(self.nodes) > 0:
            for node in self.nodes:
                self.write('bl.node(')
                self.write("package='{0}',".format(node.package), indent_level=2)
                self.write("executable='{0}',".format(node.executable), indent_level=2)
                self.write("name='{0}',".format(node.name), indent_level=2)
                if node.namespace:
                    self.write("namespace='{0}',".format(node.namespace), indent_level=2)
                if len(node.arguments) > 0:
                    self.write('cmd_args=', indent_level=2)
                    self.write_value(node.arguments, indent_level=3)
                    self.write(',', indent_level=2)
                if len(node.remappings) > 0:
                    remaps = {source: target for source, target in node.remappings}
                    self.write('remaps=', indent_level=2)
                    self.write_value(remaps, indent_level=3)
                    self.write(',', indent_level=2)
                merged = {}
                for entry in node.parameters:
                    if isinstance(entry, dict):
                        merged.update(entry)
                use_sim_time = merged.pop('use_sim_time', None)
                if use_sim_time is not None:
                    self.write('use_sim_time={0},'.format(use_sim_time), indent_level=2)
                if len(merged) > 0:
                    self.write('params=', indent_level=2)
                    self.write_value(merged, indent_level=3)
                    self.write(',', indent_level=2)
                self.write(')')
                self.write_newline()

        if len(self.processes) > 0:
            for process in self.processes:
                name = process.name.replace('process_', '')
                if isinstance(process.cmd, str):
                    self.write("bl.process('{0}', name='{1}')".format(process.cmd, name))
                else:
                    self.write('bl.process(')
                    self.write_value(process.cmd, indent_level=2)
                    self.write(", name='{0}')".format(name), indent_level=2)
                self.write_newline()

        self.close_file()
        print('Generated launch file: {0}'.format(self.launch_file.get_full_path()))
