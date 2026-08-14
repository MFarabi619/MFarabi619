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


import argparse
from pathlib import Path
import shlex
import subprocess
import sys

import yaml

MIRROR_ROOT = '/home/mfarabi/MFarabi619'
PIXI = '/home/mfarabi/.pixi/bin/pixi'

RUNTIME_SUBTREES = [
    'config', 'control', 'description', 'bringup', 'hardware_interfaces',
    'msgs', 'sensors', 'drivers', 'navigation', 'perception',
]

OLD_LAYOUT_ENTRIES = [
    'package.xml', 'setup.py', 'setup.cfg', 'resource', 'robot', 'launch',
    'meshes', 'urdf', 'test', 'lichtblick-layout.json',
]

REPO_ROOT = Path(__file__).resolve().parents[3]
ROBOTS_PATH = REPO_ROOT / 'apps/robot/config/robots'

RSYNC_FLAGS = ['-rlpgoD', '--checksum']

PWM_OVERLAY = 'dtoverlay=pwm-2chan,pin=12,func=4,pin2=13,func2=4'
FIRMWARE_CONFIG_PATH = '/boot/firmware/config.txt'


def run(*command, working_directory=None):
    subprocess.run(command, check=True, cwd=working_directory)


def ssh(host, remote_command):
    run('ssh', '-q', host, remote_command)


def ssh_with_terminal(host, remote_command):
    run('ssh', '-q', '-t', host, remote_command)


def shell_chain(*commands):
    return ' && '.join(shlex.join(command) for command in commands)


def sync(host):
    ssh(host, f'mkdir -p {MIRROR_ROOT}/zephyrproject/modules/lib/better_launch')
    run('rsync', *RSYNC_FLAGS, '--delete', '--exclude', '.git', '-e', 'ssh -q',
        'zephyrproject/modules/lib/better_launch/',
        f'{host}:{MIRROR_ROOT}/zephyrproject/modules/lib/better_launch/',
        working_directory=REPO_ROOT)
    run('rsync', *RSYNC_FLAGS, '-e', 'ssh -q',
        'apps/robot/pixi.toml', 'apps/robot/pixi.lock',
        f'{host}:{MIRROR_ROOT}/apps/robot/', working_directory=REPO_ROOT)
    for subtree in RUNTIME_SUBTREES:
        run('rsync', *RSYNC_FLAGS, '--delete', '-e', 'ssh -q',
            f'apps/robot/{subtree}/',
            f'{host}:{MIRROR_ROOT}/apps/robot/{subtree}/',
            working_directory=REPO_ROOT)


def build(host, config):
    commands = [
        ['cd', f'{MIRROR_ROOT}/apps/robot'],
        ['rm', '-rf', *OLD_LAYOUT_ENTRIES],
    ]
    if config.get('sensors'):
        commands.append([PIXI, 'install', '-e', 'jazzy'])
    commands.append([
        PIXI, 'run', 'build',
        ' '.join(RUNTIME_SUBTREES),
    ])
    ssh_with_terminal(host, shell_chain(*commands))


def provision(host, config):
    ssh(host, 'test -x ~/.pixi/bin/pixi'
        ' || curl -fsSL https://pixi.sh/install.sh | bash')
    udev = f'{MIRROR_ROOT}/apps/robot/config/udev'
    ssh_with_terminal(host, shell_chain(
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         f'{udev}/80-movidius.rules', f'{udev}/99-obsensor-libusb.rules',
         '/etc/udev/rules.d/'],
        ['sudo', 'udevadm', 'control', '--reload-rules'],
    ))
    if config['system']['hosts'][0]['board'] == 'rpi_5':
        ssh(host, f'grep -q "^{PWM_OVERLAY}" {FIRMWARE_CONFIG_PATH}'
            f' || echo "{PWM_OVERLAY}" | sudo tee -a {FIRMWARE_CONFIG_PATH} >/dev/null')


def install_units(host, robot_name):
    services = f'{MIRROR_ROOT}/apps/robot/config/services'
    has_ap = (ROBOTS_PATH / robot_name / 'hostapd.conf').is_file()
    commands = [
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         f'{services}/robot.service', '/etc/systemd/system/'],
    ]
    if has_ap:
        hostapd_config = f'{MIRROR_ROOT}/apps/robot/config/robots/{robot_name}/hostapd.conf'
        commands += [
            ['sudo', 'install', '-m', '600', '-o', 'root', '-g', 'root',
             hostapd_config, '/etc/hostapd/hostapd.conf'],
            ['sudo', 'systemctl', 'enable', 'hostapd'],
        ]
    commands.append(['sudo', 'systemctl', 'daemon-reload'])
    commands.append(['sudo', 'systemctl', 'enable', 'robot.service'])
    commands.append(['sudo', 'systemctl', 'restart', 'robot.service'])
    ssh_with_terminal(host, shell_chain(*commands))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('robot', nargs='?', default='robot1')
    robot_name = parser.parse_args().robot

    config_path = ROBOTS_PATH / robot_name / 'robot.yaml'
    if not config_path.is_file():
        sys.exit(f'{robot_name} has no robot.yaml')
    config = yaml.safe_load(config_path.read_text())

    host = config['system']['hosts'][0]['hostname']

    try:
        print(f'syncing {host}')
        sync(host)
        print('provisioning')
        provision(host, config)
        print('building')
        build(host, config)
        print('installing units')
        install_units(host, robot_name)
        print('deployed')
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)


if __name__ == '__main__':
    main()
