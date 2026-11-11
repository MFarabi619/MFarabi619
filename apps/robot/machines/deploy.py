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
import hashlib
from pathlib import Path
import shlex
import subprocess
import sys
import time

import yaml

MIRROR_ROOT = '/home/mfarabi/MFarabi619'
PIXI = '/home/mfarabi/.pixi/bin/pixi'

ROBOT_LOCAL_ENTRIES = [
    '.pixi', 'build', 'install', 'log', 'build-arm', 'install-arm']

DEVELOPMENT_ONLY_ENTRIES = ['__pycache__', 'assets']

DEAD_LAYOUT_ENTRIES = [
    'build/robot_config',
    'build/robot_bringup', 'install/share/robot_bringup',
    'build/robot_sensors', 'install/share/robot_sensors',
    'install/lib/robot_sensors',
    'build/robot_hardware_interfaces',
    'install/share/robot_hardware_interfaces',
    'install/include/robot_hardware_interfaces',
    'install/lib/librobot_hardware_interfaces.so',
    'install/share/ament_index/resource_index/packages/robot_bringup',
    'build/robot_generator_common', 'install/share/robot_generator_common',
    'install/lib/robot_generator_common',
    'install/lib/robot_description/generate_param',
    'install/lib/python3.14/site-packages/robot_generator_common',
    'install/share/ament_index/resource_index/packages/robot_generator_common',
    'install/share/ament_index/resource_index/packages/robot_hardware_interfaces',
    'install/share/ament_index/resource_index/packages/robot_sensors',
    'install/share/ament_index/resource_index/'
    'hardware_interface__pluginlib__plugin/robot_hardware_interfaces',
    'install/share/robot_simulator/config',
    'install/lib/robot_perception/collision_overlay_cpp',
    'install/lib/robot_perception/collision_overlay.py',
    'install/share/robot_control/config/generated',
    'install/share/robot_control/config/drivetrain.generated.yaml',
    'build/zed_description', 'install/share/zed_description',
    'install/share/ament_index/resource_index/packages/zed_description',
    'build/nav2_common', 'build/nav2_msgs',
    'install/include/nav2_msgs',
    'install/lib/libnav2_msgs__rosidl_generator_c.so',
    'install/lib/libnav2_msgs__rosidl_generator_py.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_c.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_cpp.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_fastrtps_c.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_fastrtps_cpp.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_introspection_c.so',
    'install/lib/libnav2_msgs__rosidl_typesupport_introspection_cpp.so',
    'install/lib/python3.14/site-packages/nav2_common',
    'install/lib/python3.14/site-packages/nav2_common-1.3.13-py3.14.egg-info',
    'install/lib/python3.14/site-packages/nav2_msgs',
    'install/lib/python3.14/site-packages/nav2_msgs-1.3.13-py3.14.egg-info',
    'install/share/nav2_common', 'install/share/nav2_msgs',
    'install/share/ament_index/resource_index/package_run_dependencies/nav2_common',
    'install/share/ament_index/resource_index/package_run_dependencies/nav2_msgs',
    'install/share/ament_index/resource_index/packages/nav2_common',
    'install/share/ament_index/resource_index/packages/nav2_msgs',
    'install/share/ament_index/resource_index/parent_prefix_path/nav2_common',
    'install/share/ament_index/resource_index/parent_prefix_path/nav2_msgs',
    'install/share/ament_index/resource_index/rosidl_interfaces/nav2_msgs',
    'install/share/ament_index/resource_index/rust_packages/nav2_msgs',
    'install/share/colcon-core/packages/nav2_common',
    'install/share/colcon-core/packages/nav2_msgs',
]

REPO_ROOT = Path(__file__).resolve().parents[3]
MACHINES_PATH = REPO_ROOT / 'apps/robot/machines'

RSYNC_FLAGS = ['-rlptgoD', '-P']

PWM_OVERLAY = 'dtoverlay=pwm-2chan,pin=12,func=4,pin2=13,func2=4'
FIRMWARE_CONFIG_PATH = '/boot/firmware/config.txt'

USB_AUTOSUSPEND_OFF = 'usbcore.autosuspend=-1'
EXTLINUX_CONFIG_PATH = '/boot/extlinux/extlinux.conf'


def run(*command, working_directory=None):
    subprocess.run(command, check=True, cwd=working_directory)


def ssh(host, remote_command):
    run('ssh', '-q', host, remote_command)


def ssh_with_terminal(host, remote_command):
    run('ssh', '-q', '-t', host, remote_command)


def shell_chain(*commands):
    return ' && '.join(shlex.join(command) for command in commands)


def is_arm_only_machine(config):
    return 'arm' in config and 'platform' not in config


def has_zed_camera(config):
    return any(
        camera['model'] == 'zed_2'
        for camera in (config.get('sensors') or {}).get('camera', []))


def environment_changes(host):
    local_lock = hashlib.sha256(
        (REPO_ROOT / 'apps/robot/pixi.lock').read_bytes()).hexdigest()
    remote_lock = subprocess.run(
        ['ssh', '-q', host,
         f'sha256sum {MIRROR_ROOT}/apps/robot/pixi.lock'],
        capture_output=True, text=True)
    return (remote_lock.returncode != 0
            or not remote_lock.stdout.startswith(local_lock))


def mirror(host, config):
    ssh(host, shell_chain(
        ['mkdir', '-p', f'{MIRROR_ROOT}/apps/robot',
         f'{MIRROR_ROOT}/vendor/better_launch',
         f'{MIRROR_ROOT}/vendor/audio_common'],
        ['rm', '-rf', f'{MIRROR_ROOT}/vendor/navigation2'],
        ['cd', f'{MIRROR_ROOT}/apps/robot'],
        ['rm', '-rf', *DEAD_LAYOUT_ENTRIES],
    ))
    for vendor_tree in ('better_launch', 'audio_common'):
        run('rsync', *RSYNC_FLAGS, '--delete', '--exclude', '.git',
            '-e', 'ssh -q', f'vendor/{vendor_tree}/',
            f'{host}:{MIRROR_ROOT}/vendor/{vendor_tree}/',
            working_directory=REPO_ROOT)
    if is_arm_only_machine(config) or has_zed_camera(config):
        for vendor_tree in (
                'ros2_link6', 'cartesian_controllers', 'mujoco_ros2_control',
                'play_motion2', 'ros2_robotiq_gripper', 'picknik_controllers',
                'serial', 'ros2_controllers', 'zed-ros2-wrapper',
                'zed-ros2-interfaces'):
            run('rsync', *RSYNC_FLAGS, '--delete', '--exclude', '.git',
                '-e', 'ssh -q', f'vendor/{vendor_tree}/',
                f'{host}:{MIRROR_ROOT}/vendor/{vendor_tree}/',
                working_directory=REPO_ROOT)
    run('rsync', *RSYNC_FLAGS, '--delete',
        *[f'--exclude={entry}' for entry in ROBOT_LOCAL_ENTRIES],
        *[f'--filter=H {entry}' for entry in DEVELOPMENT_ONLY_ENTRIES],
        '-e', 'ssh -q', 'apps/robot/',
        f'{host}:{MIRROR_ROOT}/apps/robot/', working_directory=REPO_ROOT)


def build(host, config, environment_changed):
    commands = [
        ['cd', f'{MIRROR_ROOT}/apps/robot'],
    ]
    if environment_changed:
        commands.append(['rm', '-rf', 'build', 'build-arm'])
    if is_arm_only_machine(config):
        commands.append([PIXI, 'install', '-e', 'kortex'])
        commands.append([PIXI, 'run', 'build-arm'])
    else:
        if (config.get('sensors') or {}).get('gps'):
            commands.append([PIXI, 'install', '-e', 'jazzy'])
        if has_zed_camera(config):
            commands.append([PIXI, 'run', 'build-zed'])
        commands.append([PIXI, 'run', 'build'])
    ssh_with_terminal(host, shell_chain(*commands))


def provision(host, config):
    ssh(host, 'test -x ~/.pixi/bin/pixi'
        ' || curl -fsSL https://pixi.sh/install.sh | bash')
    udev = f'{MIRROR_ROOT}/apps/robot/drivers/udev'
    services = f'{MIRROR_ROOT}/apps/robot/boot/systemd'
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
    services = f'{MIRROR_ROOT}/apps/robot/boot/systemd'
    has_hostapd_config = (MACHINES_PATH / robot_name / 'hostapd.conf').is_file()
    commands = [
        ['sudo', 'install', '-m', '644', '-o', 'root', '-g', 'root',
         f'{services}/robot.service', '/etc/systemd/system/'],
        ['sync', '/etc/systemd/system/robot.service'],
    ]
    if has_hostapd_config:
        hostapd_config = f'{MIRROR_ROOT}/apps/robot/machines/{robot_name}/hostapd.conf'
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
            cwd=REPO_ROOT / 'apps/robot')
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
        environment_changed = environment_changes(host)
        mirror(host, config)
        print('provisioning')
        provision(host, config)
        print('building')
        build(host, config, environment_changed)
        print('installing units')
        install_units(host, robot_name)
        print('verifying health')
        verify_health(robot_name)
        print('deployed healthy')
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)


if __name__ == '__main__':
    main()
