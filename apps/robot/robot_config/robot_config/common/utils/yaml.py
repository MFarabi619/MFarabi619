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
        config = yaml.load(open(path), Loader=yaml.SafeLoader)
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
    yaml_file = open(path, 'w+')
    yaml.Dumper.ignore_aliases = lambda *args: True
    yaml.dump(
        config,
        yaml_file,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=True,
    )
