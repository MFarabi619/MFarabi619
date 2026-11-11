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
import time

import yaml

MIRROR_ROOT = '/home/mfarabi/MFarabi619'
MIRROR_ROBOT_PATH = f'{MIRROR_ROOT}/apps/robot'
PIXI = '/home/mfarabi/.pixi/bin/pixi'

ROBOT_LOCAL_ENTRIES = ['.pixi', 'build', 'install', 'log']

DEVELOPMENT_ONLY_ENTRIES = ['__pycache__', 'assets']

REPO_ROOT = Path(__file__).resolve().parents[3]
ROBOT_PATH = REPO_ROOT / 'apps/robot'
MACHINES_PATH = ROBOT_PATH / 'machines'

RSYNC_FLAGS = ['-rlptgoD', '-P']

BUILD_WORKERS = 2
COMPILE_JOBS_PER_WORKER = 3

PWM_OVERLAY = 'dtoverlay=pwm-2chan,pin=12,func=4,pin2=13,func2=4'
FIRMWARE_CONFIG_PATH = '/boot/firmware/config.txt'

USB_AUTOSUSPEND_OFF = 'usbcore.autosuspend=-1'
EXTLINUX_CONFIG_PATH = '/boot/extlinux/extlinux.conf'

FLEET_VENDOR_TREES = ['better_launch', 'audio_common', 'nmea_navsat_driver']
ARM_VENDOR_TREES = [
    'ros2_link6', 'cartesian_controllers', 'mujoco_ros2_control',
    'play_motion2', 'ros2_robotiq_gripper', 'picknik_controllers', 'serial',
    'ros2_controllers']
ZED_VENDOR_TREES = ['zed-ros2-wrapper', 'zed-ros2-interfaces']


def run(*command, working_directory=None):
    subprocess.run(command, check=True, cwd=working_directory)


def ssh(host, remote_command):
    run('ssh', '-q', host, remote_command)


def ssh_with_terminal(host, remote_command):
    run('ssh', '-q', '-t', host, remote_command)


def shell_chain(*commands):
    return ' && '.join(shlex.join(command) for command in commands)


def has_zed_camera(config):
    return any(
        camera['model'] == 'zed_2'
        for camera in (config.get('sensors') or {}).get('camera', []))


def vendor_trees(config):
    trees = list(FLEET_VENDOR_TREES)
    if 'arm' in config:
        trees += ARM_VENDOR_TREES
    if has_zed_camera(config):
        trees += ZED_VENDOR_TREES
    return trees


def mirrored_package_names(host):
    listing = subprocess.run(
        ['ssh', '-q', host, shell_chain(
            ['cd', MIRROR_ROBOT_PATH],
            [PIXI, 'run', 'colcon', 'list', '--names-only'])],
        capture_output=True, text=True, check=True)
    return listing.stdout.split()


def remove_unmirrored_build_entries(host):
    keep_package_expression = [
        argument for package in mirrored_package_names(host)
        for argument in ('!', '-name', package)]
    ssh(host, shell_chain(
        ['cd', MIRROR_ROBOT_PATH],
        ['mkdir', '-p', 'build', 'install'],
        ['find', 'build', 'install', '-mindepth', '1', '-maxdepth', '1',
         *keep_package_expression, '-exec', 'rm', '-rf', '{}', '+'],
    ))


def mirror(host, config):
    ssh(host, shell_chain(
        ['mkdir', '-p', MIRROR_ROBOT_PATH, f'{MIRROR_ROOT}/vendor'],
    ))
    run('rsync', *RSYNC_FLAGS, '--delete', '--delete-excluded',
        '--exclude', '.git',
        *[f'--include=/{vendor_tree}/' for vendor_tree in vendor_trees(config)],
        '--exclude=/*',
        '-e', 'ssh -q', 'vendor/', f'{host}:{MIRROR_ROOT}/vendor/',
        working_directory=REPO_ROOT)
    run('rsync', *RSYNC_FLAGS, '--delete',
        *[f'--exclude={entry}' for entry in ROBOT_LOCAL_ENTRIES],
        *[f'--filter=H {entry}' for entry in DEVELOPMENT_ONLY_ENTRIES],
        '-e', 'ssh -q', 'apps/robot/',
        f'{host}:{MIRROR_ROBOT_PATH}/', working_directory=REPO_ROOT)


def stop_robot_service(host):
    ssh_with_terminal(
        host, '! systemctl is-active --quiet robot.service'
        ' || sudo systemctl stop robot.service')


def build(host):
    remove_unmirrored_build_entries(host)
    ssh_with_terminal(host, shell_chain(
        ['cd', MIRROR_ROBOT_PATH],
        ['env', f'MAKEFLAGS=-j{COMPILE_JOBS_PER_WORKER}',
         f'CMAKE_BUILD_PARALLEL_LEVEL={COMPILE_JOBS_PER_WORKER}',
         PIXI, 'run', 'build', '--parallel-workers', str(BUILD_WORKERS)],
    ))


def provision(host, config):
    ssh(host, 'test -x ~/.pixi/bin/pixi'
        ' || curl -fsSL https://pixi.sh/install.sh | bash')
    udev = f'{MIRROR_ROBOT_PATH}/drivers/udev'
    services = f'{MIRROR_ROBOT_PATH}/boot/systemd'
    ssh_with_terminal(host, shell_chain(
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         f'{udev}/80-movidius.rules', f'{udev}/99-obsensor-libusb.rules',
         '/etc/udev/rules.d/'],
        ['sudo', 'udevadm', 'control', '--reload-rules'],
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root', '-D',
         f'{services}/journald-persistent.conf',
         '/etc/systemd/journald.conf.d/50-persistent.conf'],
        ['sudo', 'systemctl', 'restart', 'systemd-journald'],
        ['sudo', 'systemctl', 'set-default', 'multi-user.target'],
    ))
    if config['system']['hosts'][0]['board'] == 'rpi_5':
        ssh(host, f'grep -q "^{PWM_OVERLAY}" {FIRMWARE_CONFIG_PATH}'
            f' || echo "{PWM_OVERLAY}" | sudo tee -a {FIRMWARE_CONFIG_PATH} >/dev/null')
        ssh(host, 'command -v uhubctl >/dev/null'
            ' || sudo apt-get install -y uhubctl')
    if config['system']['hosts'][0]['board'] == 'jetson_orin_nano':
        ssh(host, f'grep -q "{USB_AUTOSUSPEND_OFF}" {EXTLINUX_CONFIG_PATH}'
            f' || sudo sed -i "/^      APPEND / s/$/ {USB_AUTOSUSPEND_OFF}/"'
            f' {EXTLINUX_CONFIG_PATH}')


def install_units(host, robot_name):
    services = f'{MIRROR_ROBOT_PATH}/boot/systemd'
    has_hostapd_config = (MACHINES_PATH / robot_name / 'hostapd.conf').is_file()
    commands = [
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         f'{services}/robot.service', '/etc/systemd/system/'],
        ['sync', '/etc/systemd/system/robot.service'],
    ]
    if has_hostapd_config:
        hostapd_config = f'{MIRROR_ROBOT_PATH}/machines/{robot_name}/hostapd.conf'
        commands += [
            ['sudo', 'install', '-m', '600', '-o', 'root', '-g', 'root',
             hostapd_config, '/etc/hostapd/hostapd.conf'],
            ['sudo', 'systemctl', 'enable', 'hostapd'],
        ]
    commands.append(['sudo', 'systemctl', 'daemon-reload'])
    commands.append(['sudo', 'systemctl', 'enable', 'robot.service'])
    commands.append(['sudo', 'systemctl', 'restart', 'robot.service'])
    ssh_with_terminal(host, shell_chain(*commands))


HEALTH_DEADLINE_S = 150.0
HEALTH_RETRY_DELAY_S = 10.0


def verify_health(robot_name):
    deadline = time.monotonic() + HEALTH_DEADLINE_S
    while True:
        check = subprocess.run(
            [sys.executable, 'e2e/robot_health.py', robot_name],
            cwd=ROBOT_PATH)
        if check.returncode == 0:
            return
        if time.monotonic() >= deadline:
            sys.exit(f'{robot_name} deployed but failed its health check')
        time.sleep(HEALTH_RETRY_DELAY_S)


def verify_machine(robot_name):
    check_script = MACHINES_PATH / robot_name / 'check.sh'
    if not check_script.is_file():
        return
    check = subprocess.run(
        ['sh', str(check_script)], capture_output=True, text=True)
    findings = (check.stdout + check.stderr).strip()
    if findings:
        sys.exit(f'{robot_name} machine check failed:\n{findings}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('robot', nargs='?', default='taro')
    robot_name = parser.parse_args().robot

    config_path = MACHINES_PATH / robot_name / 'robot.yaml'
    if not config_path.is_file():
        sys.exit(f'{robot_name} has no robot.yaml')
    config = yaml.safe_load(config_path.read_text())

    host = f"{config['system']['hosts'][0]['hostname']}.local"

    try:
        print('verifying machine')
        verify_machine(robot_name)
        print(f'mirroring {host}')
        mirror(host, config)
        print('provisioning')
        provision(host, config)
        print('stopping robot service')
        stop_robot_service(host)
        print('building')
        build(host)
        print('installing units')
        install_units(host, robot_name)
        print('verifying health')
        verify_health(robot_name)
        print('deployed healthy')
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)


if __name__ == '__main__':
    main()
