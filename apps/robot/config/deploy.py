#!/usr/bin/env python3

import argparse
import shlex
import subprocess
import sys
from pathlib import Path

import yaml

MIRROR = '/home/mfarabi/MFarabi619'

RUNTIME_SUBTREES = [
    'config', 'control', 'description', 'bringup', 'hardware_interfaces',
    'msgs', 'sensors', 'drivers', 'diagnostics',
]

OLD_LAYOUT_ENTRIES = [
    'package.xml', 'setup.py', 'setup.cfg', 'resource', 'robot', 'launch',
    'meshes', 'urdf', 'test', 'lichtblick-layout.json',
]

REPO_ROOT = Path(__file__).resolve().parents[3]
ROBOTS_PATH = REPO_ROOT / 'apps/robot/config/robots'


def run(*command, working_directory=None):
    subprocess.run(command, check=True, cwd=working_directory)


def ssh(host, remote_command):
    run('ssh', '-q', host, remote_command)


def ssh_with_sudo_prompt(host, remote_command):
    run('ssh', '-q', '-t', host, remote_command)


def shell_chain(*commands):
    return ' && '.join(shlex.join(command) for command in commands)


def sync(host):
    sources = [
        'pixi.toml',
        'pixi.lock',
        *(f'apps/robot/{subtree}' for subtree in RUNTIME_SUBTREES),
    ]
    run('rsync', '-aR', '--delete', '-e', 'ssh -q', *sources, f'{host}:{MIRROR}/',
        working_directory=REPO_ROOT)


def build(host, config):
    commands = [
        ['cd', f'{MIRROR}/apps/robot'],
        ['rm', '-rf', *OLD_LAYOUT_ENTRIES],
        ['cd', MIRROR],
    ]
    if config.get('sensors'):
        commands.append(['pixi', 'install', '-e', 'jazzy'])
    commands.append(['pixi', 'run', 'build'])
    ssh(host, shell_chain(*commands))


def install_units(host, robot_name):
    unit = f'{MIRROR}/apps/robot/config/services/robot.service'
    commands = [
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         unit, '/etc/systemd/system/'],
    ]
    restart_units = ['robot.service']
    if (ROBOTS_PATH / robot_name / 'hostapd.conf').is_file():
        hostapd_config = f'{MIRROR}/apps/robot/config/robots/{robot_name}/hostapd.conf'
        commands.append(
            ['sudo', 'install', '-m', '600', '-o', 'root', '-g', 'root',
             hostapd_config, '/etc/hostapd/hostapd.conf'])
        restart_units.insert(0, 'hostapd')
    commands.append(['sudo', 'systemctl', 'daemon-reload'])
    commands.append(['sudo', 'systemctl', 'try-restart', *restart_units])
    ssh_with_sudo_prompt(host, shell_chain(*commands))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('robot', nargs='?', default='robot0')
    robot_name = parser.parse_args().robot

    config_path = ROBOTS_PATH / robot_name / 'robot.yaml'
    if not config_path.is_file():
        sys.exit(f'{robot_name} has no robot.yaml')
    config = yaml.safe_load(config_path.read_text())

    host = config['system']['hosts'][0]['hostname']

    try:
        sync(host)
        build(host, config)
        install_units(host, robot_name)
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)


if __name__ == '__main__':
    main()
