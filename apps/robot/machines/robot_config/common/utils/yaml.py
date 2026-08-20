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

import yaml
from yaml.constructor import ConstructorError
from yaml.scanner import ScannerError


# Get Valid Path
def find_valid_path(path, cwd=None):
    abspath = path
    if cwd:
        relpath = os.path.join(cwd, path)
    else:
        relpath = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), path)
    if not os.path.isfile(abspath) and not os.path.isfile(relpath):
        return None
    if os.path.isfile(abspath):
        path = abspath
    elif os.path.isfile(relpath):
        path = relpath
    return path


def read_yaml(path: str) -> dict:
    orig = path
    # Check YAML Path
    path = find_valid_path(path, os.getcwd())
    if not path:
        raise FileNotFoundError(f'YAML file {orig} could not be found')
    # Check YAML can be Opened
    try:
        with open(path) as file:
            config = yaml.load(file, Loader=yaml.SafeLoader)
    except ScannerError:
        raise ScannerError(f'YAML file {orig} is not well-formed')
    except ConstructorError:
        raise ConstructorError(f'YAML file "{orig}" is attempting to create unsafe objects')
    # Check contents are a Dictionary
    if not isinstance(config, dict):
        raise TypeError(f'YAML file "{orig}" is not a dictionary')
    return config


def write_yaml(path: str, config: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    yaml.Dumper.ignore_aliases = lambda *args: True
    with open(path, 'w+') as yaml_file:
        yaml.dump(
            config,
            yaml_file,
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
        )
