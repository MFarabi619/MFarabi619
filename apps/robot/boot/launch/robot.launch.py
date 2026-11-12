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


from contextlib import nullcontext
import os

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher
from robot_boot.launch_policy import TF_REMAPS, include, write_parameter_overrides_file
from robot_boot.urdf import ground_offset_meters, wheel_geometry
from robot_boot.zenoh_router import (
    ZENOH_CLIENT_CONFIG_OVERRIDE, ZENOH_ROUTER_CONFIG_OVERRIDE, ensure_zenoh_router,
    wait_for_zenoh_router)
from robot_machines.machine import (
    DOMAINS, LUXONIS_OAK_D_PRO_W_POE_MODEL, LUXONIS_OAK_MODELS, STEREOLABS_ZED_MODEL,
    load_machine, load_machine_for_this_host)

ZENOH_ROUTER_SERVICE_MAX_ATTEMPTS = 600
ZENOH_ROUTER_SERVICE_RETRY_DELAY_SECONDS = 1.0
STEREOLABS_ZED_DEFAULT_POINT_CLOUD_RATE_HZ = 10.0
FOLLOWED_SURFACES = ('sidewalk', 'park_path', 'path')
LUXONIS_OAK_LASERSCAN_ARGUMENTS = {
    'max_height': 0.6, 'range_min': 0.2, 'range_max': 3.0, 'scan_time': 0.05}


def resolve_line(pins, pin):
    entry = pins[pin]
    return entry['gpio_chip'], entry['line']


def resolve_pwm(pins, pin):
    entry = pins[pin]
    return entry['pwm_chip'], entry['pwm_channel']


def pwm_channels(pins, drivetrain):
    left_chip, left_channel = resolve_pwm(pins, drivetrain.left.pwm_pin)
    right_chip, right_channel = resolve_pwm(pins, drivetrain.right.pwm_pin)
    return {
        'left_pwm_chip': left_chip, 'left_pwm_channel': left_channel,
        'right_pwm_chip': right_chip, 'right_pwm_channel': right_channel,
    }


def direction_lines(pins, drivetrain):
    left_chip, left_line = resolve_line(pins, drivetrain.left.dir_pin)
    right_chip, right_line = resolve_line(pins, drivetrain.right.dir_pin)
    if left_chip != right_chip:
        raise RuntimeError('left and right direction pins must share one gpio chip')
    return {'gpio_chip': left_chip, 'left_dir_line': left_line, 'right_dir_line': right_line}


def flash_declarations(flash):
    declarations = []
    for code, setting in flash.items():
        if isinstance(setting, dict):
            declarations += [
                f'{code} {channel} {value}'
                for channel, value in setting.items()
            ]
        else:
            declarations.append(f'{code} {setting}')
    return declarations


def launch_motor_driver(machine, drivetrain_model, max_wheel_speed, wheel_radius):
    drivetrain = machine.platform.drivetrain
    if drivetrain_model == 'odrive_usb':
        include(
            'robot_drivers', 'odrive_motor_driver.launch.py',
            gear_ratio=drivetrain.gear_ratio,
            max_wheel_speed=max_wheel_speed,
            left_serial_number=drivetrain.left.serial_number,
            left_is_reversed=drivetrain.left.is_reversed,
            right_serial_number=drivetrain.right.serial_number,
            right_is_reversed=drivetrain.right.is_reversed,
        )
    elif drivetrain_model == 'svd48v':
        include(
            'robot_drivers', 'svd48v_motor_driver.launch.py',
            serial_port=drivetrain.serial_port,
            baud_rate=drivetrain.baud_rate,
            max_wheel_speed=max_wheel_speed,
            acceleration_rpm_per_second=drivetrain.acceleration_rpm_per_second,
            speed_smoothing_time=drivetrain.speed_smoothing_time,
            left_is_reversed=drivetrain.left.is_reversed,
            right_is_reversed=drivetrain.right.is_reversed,
        )
    elif drivetrain_model == 'roboteq':
        full_scale_linear_velocity_meters_per_second = (
            drivetrain.full_scale_linear_velocity_meters_per_second)
        include(
            'robot_drivers', 'roboteq_motor_driver.launch.py',
            serial_port=drivetrain.serial_port,
            baud_rate=drivetrain.baud_rate,
            counts_per_revolution=drivetrain.counts_per_revolution,
            control_mode=(
                'speed' if drivetrain.control_mode is None else drivetrain.control_mode),
            left_is_reversed=drivetrain.left.is_reversed,
            right_is_reversed=drivetrain.right.is_reversed,
            max_wheel_speed=max_wheel_speed or 0.0,
            full_scale_wheel_speed=(
                full_scale_linear_velocity_meters_per_second / wheel_radius
                if full_scale_linear_velocity_meters_per_second is not None else 0.0),
            flash=','.join(flash_declarations(drivetrain.roboteq.get('flash', {}))),
        )
    elif drivetrain_model == 'mock':
        pass
    elif drivetrain_model == 'rc_pulse':
        include(
            'robot_drivers', 'rc_pulse_motor_driver.launch.py',
            max_wheel_speed=max_wheel_speed,
            left_is_reversed=drivetrain.left.is_reversed,
            right_is_reversed=drivetrain.right.is_reversed,
            **pwm_channels(machine.board_pins, drivetrain),
        )
    else:
        pins = machine.board_pins
        include(
            'robot_drivers', 'pwm_dir_motor_driver.launch.py',
            pwm_frequency_hz=drivetrain.pwm_frequency_hz,
            max_wheel_speed=max_wheel_speed,
            min_duty_fraction=(
                0.0 if drivetrain.min_duty_fraction is None
                else drivetrain.min_duty_fraction),
            left_forward_level=drivetrain.left.forward_level,
            right_forward_level=drivetrain.right.forward_level,
            **pwm_channels(pins, drivetrain),
            **direction_lines(pins, drivetrain),
        )


def launch_platform(machine, drivetrain_model, urdf_path, depth_camera):
    drivetrain = machine.platform.drivetrain
    drivetrain_model = drivetrain_model or drivetrain.model
    wheel_separation, wheel_radius = wheel_geometry(urdf_path)
    motion_limits = drivetrain.motion_limits(drivetrain_model)
    max_linear_velocity_meters_per_second = motion_limits.get(
        'max_linear_velocity_meters_per_second')
    max_wheel_speed = (
        max_linear_velocity_meters_per_second / wheel_radius
        if max_linear_velocity_meters_per_second is not None else None)
    collision_guarded = machine.platform.collision_guarded and depth_camera is not None

    robot_state_publisher(
        urdf_path,
        node_name='robot_state_publisher',
        anonymous=False,
        remaps=TF_REMAPS,
    )
    launch_motor_driver(machine, drivetrain_model, max_wheel_speed, wheel_radius)
    include(
        'robot_boot', 'controller_manager.launch.py',
        wheel_separation=wheel_separation,
        wheel_radius=wheel_radius,
        **motion_limits,
    )

    rc_receiver = machine.platform.rc_receiver
    if rc_receiver and rc_receiver.launch_enabled:
        pins = machine.board_pins
        channel_1_chip, channel_1_line = resolve_line(pins, rc_receiver.channel_1_pin)
        channel_2_chip, channel_2_line = resolve_line(pins, rc_receiver.channel_2_pin)
        if channel_1_chip != channel_2_chip:
            raise RuntimeError('rc channel pins must share one gpio chip')
        include(
            'robot_drivers', 'rc_receiver_joy.launch.py',
            gpio_chip=channel_1_chip,
            channel_1_line=channel_1_line,
            channel_2_line=channel_2_line,
            tank_mixed=rc_receiver.tank_mixed,
        )

    include(
        'robot_boot', 'twist_mux.launch.py',
        cmd_vel_out='platform/cmd_vel_raw' if collision_guarded else 'platform/cmd_vel',
    )
    if collision_guarded:
        include(
            'robot_boot', 'collision_monitor.launch.py',
            point_cloud_topic=f'sensors/{depth_camera.name}/depth/points')


def launch_manipulation(bl, machine):
    include(
        'robot_manipulation', f'{machine.arm.model}.launch.py',
        description_package=machine.arm.description_package,
        moveit_package=machine.arm.moveit_package,
        moveit_robot_name=machine.arm.moveit_robot_name,
        gripper=machine.arm.gripper,
        motions_file=bl.find('robot_machines', 'motions.yaml', subdir=machine.name),
    )


def camera_height_above_ground_meters(depth_camera, urdf_path):
    if not depth_camera:
        return 0.0
    offset_meters = ground_offset_meters(urdf_path) if urdf_path else 0.0
    return float(depth_camera.xyz[2]) - offset_meters


def camera_arguments(bl, camera, point_cloud_enabled):
    if camera.model == STEREOLABS_ZED_MODEL:
        x, y, z = camera.xyz
        roll, pitch, yaw = camera.rpy
        return {
            'parent_frame': camera.parent,
            'x': x, 'y': y, 'z': z, 'roll': roll, 'pitch': pitch, 'yaw': yaw,
            'overrides_file': write_parameter_overrides_file({camera.name: camera.parameters}),
        }
    arguments = dict(camera.parameters)
    if camera.model == LUXONIS_OAK_D_PRO_W_POE_MODEL:
        arguments['detects_on_camera'] = camera.detects_on_camera
        arguments['model_path'] = bl.find('robot_perception', 'yolov8n_coco_640x352.blob')
    else:
        arguments['point_cloud_enabled'] = point_cloud_enabled
    return arguments


def laserscan_arguments(camera):
    if camera.model in LUXONIS_OAK_MODELS:
        return LUXONIS_OAK_LASERSCAN_ARGUMENTS
    if camera.model == STEREOLABS_ZED_MODEL:
        point_cloud_freq = camera.parameters.get('depth', {}).get(
            'point_cloud_freq', STEREOLABS_ZED_DEFAULT_POINT_CLOUD_RATE_HZ)
        return {'scan_time': 1.0 / point_cloud_freq}
    return {'scan_time': 1.0 / camera.parameters['depth_frames_per_second']}


def launch_sensors(bl, machine):
    point_cloud_enabled = machine.point_cloud_enabled
    for gps in machine.sensors.gps:
        ntrip = gps.ntrip or {}
        include(
            'robot_drivers', f'{gps.model}.launch.py',
            gps=gps.name,
            flash=','.join(f'{key}={value}' for key, value in gps.flash.items()),
            ntrip_mountpoint=ntrip.get('mountpoint', ''),
            ntrip_username=ntrip.get('username', ''),
            **gps.parameters,
        )
    for imu in machine.sensors.imu:
        include('robot_drivers', f'{imu.model}.launch.py', imu=imu.name, **imu.parameters)
    for camera in machine.enabled_cameras:
        include(
            'robot_drivers', f'{camera.model}.launch.py',
            camera=camera.name, **camera_arguments(bl, camera, point_cloud_enabled))
        if point_cloud_enabled and camera.has_depth:
            include(
                'robot_boot', 'point_cloud_to_laserscan.launch.py',
                camera=camera.name, **laserscan_arguments(camera))


def launch_perception(machine, depth_camera, camera_height_meters, overrides_file):
    behaviors = machine.behaviors
    if behaviors.hand_gesture_teleop:
        include('robot_perception', 'hand_gesture_teleop.launch.py')
    if behaviors.weeding:
        include('robot_perception', 'weeding.launch.py')
    if depth_camera is None:
        return
    if machine.point_cloud_enabled:
        include('robot_perception', 'collision_overlay.launch.py', camera=depth_camera.name)
    include(
        'robot_perception', 'follow.launch.py',
        camera=depth_camera.name,
        image_topic=(
            f'sensors/{depth_camera.name}/color/image_raw/compressed'
            if depth_camera.publishes_compressed_color else ''),
        has_on_camera_detector=depth_camera.has_on_camera_detector,
        overrides_file=overrides_file,
    )
    if behaviors.line_follow:
        include(
            'robot_perception', 'line_follow.launch.py',
            camera=depth_camera.name,
            overrides_file=overrides_file,
        )
    for surface in FOLLOWED_SURFACES:
        if getattr(behaviors, f'{surface}_follow'):
            include(
                'robot_perception', 'surface_follow.launch.py',
                surface=surface,
                camera=depth_camera.name,
                camera_height_meters=camera_height_meters,
                overrides_file=overrides_file,
            )
    if behaviors.harvest_lane:
        include(
            'robot_perception', 'harvest_lane.launch.py',
            camera=depth_camera.name,
            camera_height_meters=camera_height_meters,
            camera_lateral_offset_meters=float(depth_camera.xyz[1]),
            overrides_file=overrides_file,
        )


def launch_navigation(machine, depth_camera, overrides_file):
    if machine.behaviors.nav2_person_follow:
        include('robot_boot', 'nav2_person_follow.launch.py')
    if machine.behaviors.gps_navigation and machine.sensors.gps and depth_camera:
        include(
            'robot_boot', 'gps_navigation.launch.py',
            scan_topic=f'sensors/{depth_camera.name}/scan',
            overrides_file=overrides_file,
        )


@launch_this
def robot(robot: str = '', drivetrain_model: str = '', domain: str = ''):
    if domain and domain not in DOMAINS:
        raise RuntimeError(f'unknown domain {domain!r}; choose one of {", ".join(DOMAINS)}')
    machine = load_machine(robot) if robot else load_machine_for_this_host()
    namespace = machine.namespace
    depth_camera = machine.depth_camera
    bl = BetterLaunch()
    if machine.platform:
        urdf_path = bl.find('robot_description', 'robot.urdf', subdir=f'urdf/{machine.name}')
    else:
        urdf_path = ''
    camera_height_meters = camera_height_above_ground_meters(depth_camera, urdf_path)
    overrides_file = write_parameter_overrides_file(machine.ros_parameters)

    def launches(candidate_domain):
        return not domain or domain == candidate_domain

    os.environ['ZENOH_CONFIG_OVERRIDE'] = ZENOH_CLIENT_CONFIG_OVERRIDE
    if domain:
        if not wait_for_zenoh_router(
                ZENOH_ROUTER_SERVICE_MAX_ATTEMPTS, ZENOH_ROUTER_SERVICE_RETRY_DELAY_SECONDS):
            raise RuntimeError(
                'no zenoh router listening; start robot-zenoh-router.service')
    else:
        ensure_zenoh_router(
            bl, env={'ZENOH_CONFIG_OVERRIDE': ZENOH_ROUTER_CONFIG_OVERRIDE},
            max_attempts=ZENOH_ROUTER_SERVICE_MAX_ATTEMPTS,
            retry_delay_seconds=ZENOH_ROUTER_SERVICE_RETRY_DELAY_SECONDS)

    with bl.group(namespace) if namespace else nullcontext():
        if launches('platform'):
            if machine.platform:
                launch_platform(machine, drivetrain_model, urdf_path, depth_camera)
            if machine.foxglove_enabled:
                include('robot_boot', 'foxglove_bridge.launch.py')
            include('robot_boot', 'diagnostic_aggregator.launch.py')
            if machine.sensors.gps:
                include(
                    'robot_boot', 'robot_localization.launch.py',
                    gps_topic_prefix=f'sensors/{machine.sensors.gps[0].name}')
        if launches('manipulation') and machine.arm:
            launch_manipulation(bl, machine)
        if launches('sensors'):
            launch_sensors(bl, machine)
        if launches('perception'):
            launch_perception(machine, depth_camera, camera_height_meters, overrides_file)
        if launches('navigation'):
            launch_navigation(machine, depth_camera, overrides_file)
