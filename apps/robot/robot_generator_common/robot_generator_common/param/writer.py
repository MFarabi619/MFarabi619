import os

from robot_generator_common.common import ParamFile


class ParamWriter():
    tab = '  '

    def __init__(self, param_file: ParamFile):
        self.param_file = param_file
        os.makedirs(os.path.dirname(self.param_file.full_path), exist_ok=True)
        self.file = open(self.param_file.full_path, 'w+')

    def write(self, string, indent_level=1):
        self.file.write('{0}{1}\n'.format(self.tab * indent_level, string))

    def write_key_value_pair(self, key: str, value, indent_level=1):
        self.write(f'{key}: {value}', indent_level=indent_level)

    def write_string(self, key: str, value: str, indent_level=1):
        self.write(f"{key}: '{value}'", indent_level=indent_level)

    def write_dictionary(self, key: str, dictionary: dict, indent_level=1):
        self.write(f'{key}:', indent_level=indent_level)
        for k in dictionary:
            self.write_obj(k, dictionary[k], indent_level + 1)

    def write_obj(self, key: str, obj: object, indent_level=1):
        if isinstance(obj, dict):
            self.write_dictionary(key, obj, indent_level)
        elif isinstance(obj, str):
            self.write_string(key, obj, indent_level)
        else:
            self.write_key_value_pair(key, obj, indent_level)

    def write_file(self):
        ros_parameters = self.param_file.to_ros_parameters()
        for k in ros_parameters:
            self.write_obj(k, ros_parameters[k], indent_level=0)
        self.file.close()
