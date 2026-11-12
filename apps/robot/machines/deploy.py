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

from robot_machines.machine import DOMAINS, MachineError, load_machine

MIRROR_ROOT = '/home/mfarabi/MFarabi619'
SYSTEMD_UNITS = ('robot.service', 'robot-zenoh-router.service', 'robot@.service')
MIRROR_ROBOT_ROOT = f'{MIRROR_ROOT}/apps/robot'
PIXI_PATH = '/home/mfarabi/.pixi/bin/pixi'

ROBOT_LOCAL_ENTRIES = ['.pixi', 'build', 'install', 'log']

DEVELOPMENT_ONLY_ENTRIES = ['__pycache__', 'assets']

REPO_ROOT = Path(__file__).resolve().parents[3]
ROBOT_ROOT = REPO_ROOT / 'apps/robot'
MACHINES_DIRECTORY = ROBOT_ROOT / 'machines'
UDEV_RULES_DIRECTORY = ROBOT_ROOT / 'drivers' / 'udev'

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
STEREOLABS_ZED_VENDOR_TREES = ['zed-ros2-wrapper', 'zed-ros2-interfaces']


def run(*command, working_directory=None):
    subprocess.run(command, check=True, cwd=working_directory)


def ssh(mdns_hostname, remote_command):
    run('ssh', '-q', mdns_hostname, remote_command)


def ssh_with_terminal(mdns_hostname, remote_command):
    run('ssh', '-q', '-t', mdns_hostname, remote_command)


def shell_chain(*commands):
    return ' && '.join(shlex.join(command) for command in commands)


def vendor_trees(machine):
    trees = list(FLEET_VENDOR_TREES)
    if machine.has_arm:
        trees += ARM_VENDOR_TREES
    if machine.has_stereolabs_zed:
        trees += STEREOLABS_ZED_VENDOR_TREES
    return trees


def mirrored_package_names(mdns_hostname):
    completed = subprocess.run(
        ['ssh', '-q', mdns_hostname, shell_chain(
            ['cd', MIRROR_ROBOT_ROOT],
            [PIXI_PATH, 'run', 'colcon', 'list', '--names-only'])],
        capture_output=True, text=True, check=True)
    return completed.stdout.split()


def remove_unmirrored_build_entries(mdns_hostname):
    keep_package_expression = [
        argument for package in mirrored_package_names(mdns_hostname)
        for argument in ('!', '-name', package)]
    ssh(mdns_hostname, shell_chain(
        ['cd', MIRROR_ROBOT_ROOT],
        ['mkdir', '-p', 'build', 'install'],
        ['find', 'build', 'install', '-mindepth', '1', '-maxdepth', '1',
         *keep_package_expression, '-exec', 'rm', '-rf', '{}', '+'],
    ))


def mirror(mdns_hostname, machine):
    ssh(mdns_hostname, shell_chain(
        ['mkdir', '-p', MIRROR_ROBOT_ROOT, f'{MIRROR_ROOT}/vendor'],
    ))
    run('rsync', *RSYNC_FLAGS, '--delete', '--delete-excluded',
        '--exclude', '.git',
        *[f'--include=/{vendor_tree}/' for vendor_tree in vendor_trees(machine)],
        '--exclude=/*',
        '-e', 'ssh -q', 'vendor/', f'{mdns_hostname}:{MIRROR_ROOT}/vendor/',
        working_directory=REPO_ROOT)
    run('rsync', *RSYNC_FLAGS, '--delete',
        *[f'--exclude={entry}' for entry in ROBOT_LOCAL_ENTRIES],
        *[f'--filter=H {entry}' for entry in DEVELOPMENT_ONLY_ENTRIES],
        '-e', 'ssh -q', 'apps/robot/',
        f'{mdns_hostname}:{MIRROR_ROBOT_ROOT}/', working_directory=REPO_ROOT)


def stop_robot_service(mdns_hostname):
    ssh_with_terminal(
        mdns_hostname, '! systemctl is-active --quiet robot.service'
        ' || sudo systemctl stop robot.service')


def build(mdns_hostname):
    remove_unmirrored_build_entries(mdns_hostname)
    ssh_with_terminal(mdns_hostname, shell_chain(
        ['cd', MIRROR_ROBOT_ROOT],
        ['env', f'MAKEFLAGS=-j{COMPILE_JOBS_PER_WORKER}',
         f'CMAKE_BUILD_PARALLEL_LEVEL={COMPILE_JOBS_PER_WORKER}',
         PIXI_PATH, 'run', 'build', '--parallel-workers', str(BUILD_WORKERS)],
    ))


def provision(mdns_hostname, machine):
    ssh(mdns_hostname, 'test -x ~/.pixi/bin/pixi'
        ' || curl -fsSL https://pixi.sh/install.sh | bash')
    udev_rules_directory = f'{MIRROR_ROBOT_ROOT}/drivers/udev'
    systemd_directory = f'{MIRROR_ROBOT_ROOT}/boot/systemd'
    ssh_with_terminal(mdns_hostname, shell_chain(
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         *[f'{udev_rules_directory}/{rules_file.name}'
           for rules_file in sorted(UDEV_RULES_DIRECTORY.glob('*.rules'))],
         '/etc/udev/rules.d/'],
        ['sudo', 'udevadm', 'control', '--reload-rules'],
        ['sudo', 'udevadm', 'trigger'],
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root', '-D',
         f'{systemd_directory}/journald-persistent.conf',
         '/etc/systemd/journald.conf.d/50-persistent.conf'],
        ['sudo', 'systemctl', 'restart', 'systemd-journald'],
        ['sudo', 'systemctl', 'set-default', 'multi-user.target'],
    ))
    if machine.board == 'rpi_5':
        ssh(mdns_hostname, f'grep -q "^{PWM_OVERLAY}" {FIRMWARE_CONFIG_PATH}'
            f' || echo "{PWM_OVERLAY}" | sudo tee -a {FIRMWARE_CONFIG_PATH} >/dev/null')
        ssh(mdns_hostname, 'command -v uhubctl >/dev/null'
            ' || sudo apt-get install -y uhubctl')
    if machine.board == 'jetson_orin_nano':
        ssh(mdns_hostname, f'grep -q "{USB_AUTOSUSPEND_OFF}" {EXTLINUX_CONFIG_PATH}'
            f' || sudo sed -i "/^      APPEND / s/$/ {USB_AUTOSUSPEND_OFF}/"'
            f' {EXTLINUX_CONFIG_PATH}')


def install_units(mdns_hostname, machine):
    systemd_directory = f'{MIRROR_ROBOT_ROOT}/boot/systemd'
    has_hostapd_config = (MACHINES_DIRECTORY / machine.name / 'hostapd.conf').is_file()
    commands = [
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         *[f'{systemd_directory}/{unit}' for unit in SYSTEMD_UNITS], '/etc/systemd/system/'],
        ['sudo', 'install', '-m', '755', '-o', 'root', '-g', 'root',
         f'{systemd_directory}/robot-yaml-watch', '/usr/local/bin/'],
        ['sync', *[f'/etc/systemd/system/{unit}' for unit in SYSTEMD_UNITS]],
    ]
    if has_hostapd_config:
        hostapd_config_path = f'{MIRROR_ROBOT_ROOT}/machines/{machine.name}/hostapd.conf'
        commands += [
            ['sudo', 'install', '-m', '600', '-o', 'root', '-g', 'root',
             hostapd_config_path, '/etc/hostapd/hostapd.conf'],
            ['sudo', 'systemctl', 'enable', 'hostapd'],
        ]
    commands.append(['sudo', 'systemctl', 'daemon-reload'])
    for domain in DOMAINS:
        verb = 'enable' if domain in machine.domains else 'disable'
        commands.append(['sudo', 'systemctl', verb, f'robot@{domain}.service'])
    commands.append(
        ['sudo', 'systemctl', 'enable', 'robot.service', 'robot-zenoh-router.service'])
    commands.append(['sudo', 'systemctl', 'restart', 'robot.service'])
    ssh_with_terminal(mdns_hostname, shell_chain(*commands))


HEALTH_DEADLINE_SECONDS = 150.0
HEALTH_RETRY_DELAY_SECONDS = 10.0


def verify_health(robot_name):
    deadline = time.monotonic() + HEALTH_DEADLINE_SECONDS
    while True:
        completed = subprocess.run(
            [sys.executable, 'e2e/robot_health.py', robot_name],
            cwd=ROBOT_ROOT)
        if completed.returncode == 0:
            return
        if time.monotonic() >= deadline:
            sys.exit(f'{robot_name} deployed but failed its health check')
        time.sleep(HEALTH_RETRY_DELAY_SECONDS)


def verify_machine(robot_name):
    check_script = MACHINES_DIRECTORY / robot_name / 'check.sh'
    if not check_script.is_file():
        return
    completed = subprocess.run(
        ['sh', str(check_script)], capture_output=True, text=True)
    findings = (completed.stdout + completed.stderr).strip()
    if findings:
        sys.exit(f'{robot_name} machine check failed:\n{findings}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('robot', nargs='?', default='taro')
    robot = parser.parse_args().robot

    try:
        machine = load_machine(robot)
    except MachineError as error:
        sys.exit(str(error))
    mdns_hostname = f'{machine.hostname}.local'

    try:
        print('verifying machine')
        verify_machine(robot)
        print(f'mirroring {mdns_hostname}')
        mirror(mdns_hostname, machine)
        print('provisioning')
        provision(mdns_hostname, machine)
        print('stopping robot service')
        stop_robot_service(mdns_hostname)
        print('building')
        build(mdns_hostname)
        print('installing units')
        install_units(mdns_hostname, machine)
        print('verifying health')
        verify_health(robot)
        print('deployed healthy')
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)


if __name__ == '__main__':
    main()
