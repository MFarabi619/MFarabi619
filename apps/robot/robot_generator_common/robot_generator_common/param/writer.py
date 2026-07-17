import os

from robot_generator_common.common import ParamFile


class ParamWriter():
    INDENT_UNIT = '  '

    def __init__(self, param_file: ParamFile):
        self.param_file = param_file
        os.makedirs(os.path.dirname(self.param_file.full_path), exist_ok=True)
        self.file = open(self.param_file.full_path, 'w+')

    def write(self, line, indent_level=1):
        self.file.write('{0}{1}\n'.format(self.INDENT_UNIT * indent_level, line))

    def write_key_value_pair(self, key: str, value, indent_level=1):
        self.write(f'{key}: {value}', indent_level=indent_level)

    def write_string(self, key: str, value: str, indent_level=1):
        self.write(f"{key}: '{value}'", indent_level=indent_level)

    def write_dictionary(self, key: str, dictionary: dict, indent_level=1):
        self.write(f'{key}:', indent_level=indent_level)
        for entry_key in dictionary:
            self.write_value(entry_key, dictionary[entry_key], indent_level + 1)

    def write_value(self, key: str, value: object, indent_level=1):
        if isinstance(value, dict):
            self.write_dictionary(key, value, indent_level)
        elif isinstance(value, str):
            self.write_string(key, value, indent_level)
        else:
            self.write_key_value_pair(key, value, indent_level)

    def write_file(self):
        ros_parameters = self.param_file.to_ros_parameters()
        for entry_key in ros_parameters:
            self.write_value(entry_key, ros_parameters[entry_key], indent_level=0)
        self.file.close()
