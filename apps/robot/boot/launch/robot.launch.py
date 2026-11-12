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
from robot_boot.launch_policy import TF_REMAPS, include, parameter_overrides_file
from robot_boot.urdf import ground_offset, wheel_geometry
from robot_boot.zenoh_router import ensure_router
from robot_machines.machine import (
    ORBBEC_CAMERA_MODEL, ZED_CAMERA_MODEL, load_machine, load_machine_for_this_host)

CLIENT_CONFIG_OVERRIDE = 'mode="client"'
ROUTER_CONFIG_OVERRIDE = 'mode="router"'
FOLLOWED_SURFACES = ('sidewalk', 'park_path', 'path')
ARM_LAUNCH_FILES = {'kinova_link_6': 'kinova_link6.launch.py'}
OAK_LASERSCAN_SETTINGS = {
    'max_height': 0.6, 'range_min': 0.2, 'range_max': 3.0, 'scan_time': 0.05}


def resolve_line(pins, pin):
    entry = pins[pin]
    return entry['gpio_chip'], entry['line']


def resolve_pwm(pins, pin):
    entry = pins[pin]
    return entry['pwm_chip'], entry['pwm_channel']


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


def motor_driver(machine, drivetrain_model, max_wheel_speed, wheel_radius):
    drivetrain = machine.platform.drivetrain
    if drivetrain_model == 'odrive_usb':
        include(
            'robot_boot', 'odrive_motor_driver.launch.py',
            gear_ratio=drivetrain.gear_ratio,
            max_wheel_speed=max_wheel_speed,
            left_serial=drivetrain.left.serial,
            left_reversed=drivetrain.left.is_reversed,
            right_serial=drivetrain.right.serial,
            right_reversed=drivetrain.right.is_reversed,
        )
    elif drivetrain_model == 'svd48v':
        include(
            'robot_boot', 'svd48v_motor_driver.launch.py',
            serial_port=drivetrain.serial_port,
            baud_rate=drivetrain.baud_rate,
            max_wheel_speed=max_wheel_speed,
            acceleration_rpm_per_second=drivetrain.acceleration_rpm_per_second,
            speed_smoothing_time=drivetrain.speed_smoothing_time,
            left_reversed=drivetrain.left.is_reversed,
            right_reversed=drivetrain.right.is_reversed,
        )
    elif drivetrain_model == 'roboteq':
        full_scale_linear_velocity = drivetrain.full_scale_linear_velocity_meters_per_second
        include(
            'robot_boot', 'roboteq_motor_driver.launch.py',
            serial_port=drivetrain.serial_port,
            baud_rate=drivetrain.baud_rate,
            counts_per_revolution=drivetrain.counts_per_revolution,
            control_mode=(
                'speed' if drivetrain.control_mode is None else drivetrain.control_mode),
            left_reversed=drivetrain.left.is_reversed,
            right_reversed=drivetrain.right.is_reversed,
            max_wheel_speed=max_wheel_speed or 0.0,
            full_scale_wheel_speed=(
                full_scale_linear_velocity / wheel_radius
                if full_scale_linear_velocity is not None else 0.0),
            flash=','.join(flash_declarations(drivetrain.roboteq.get('flash', {}))),
        )
    elif drivetrain_model == 'mock':
        pass
    elif drivetrain_model == 'rc_pulse':
        pins = machine.board_pins
        left_pwm_chip, left_pwm_channel = resolve_pwm(pins, drivetrain.left.pwm_pin)
        right_pwm_chip, right_pwm_channel = resolve_pwm(pins, drivetrain.right.pwm_pin)
        include(
            'robot_boot', 'rc_pulse_motor_driver.launch.py',
            max_wheel_speed=max_wheel_speed,
            left_pwm_chip=left_pwm_chip,
            left_pwm_channel=left_pwm_channel,
            left_reversed=drivetrain.left.is_reversed,
            right_pwm_chip=right_pwm_chip,
            right_pwm_channel=right_pwm_channel,
            right_reversed=drivetrain.right.is_reversed,
        )
    else:
        pins = machine.board_pins
        left_pwm_chip, left_pwm_channel = resolve_pwm(pins, drivetrain.left.pwm_pin)
        right_pwm_chip, right_pwm_channel = resolve_pwm(pins, drivetrain.right.pwm_pin)
        left_dir_chip, left_dir_line = resolve_line(pins, drivetrain.left.dir_pin)
        right_dir_chip, right_dir_line = resolve_line(pins, drivetrain.right.dir_pin)
        if left_dir_chip != right_dir_chip:
            raise RuntimeError('left and right direction pins must share one gpio chip')
        include(
            'robot_boot', 'pwm_dir_motor_driver.launch.py',
            gpio_chip=left_dir_chip,
            pwm_frequency_hz=drivetrain.pwm_frequency_hz,
            max_wheel_speed=max_wheel_speed,
            min_duty=0.0 if drivetrain.min_duty is None else drivetrain.min_duty,
            left_pwm_chip=left_pwm_chip,
            left_pwm_channel=left_pwm_channel,
            left_dir_line=left_dir_line,
            left_forward_level=drivetrain.left.forward_level,
            right_pwm_chip=right_pwm_chip,
            right_pwm_channel=right_pwm_channel,
            right_dir_line=right_dir_line,
            right_forward_level=drivetrain.right.forward_level,
        )


def platform(machine, drivetrain_model, urdf_path, depth_camera):
    drivetrain = machine.platform.drivetrain
    drivetrain_model = drivetrain_model or drivetrain.model
    wheel_separation, wheel_radius = wheel_geometry(urdf_path)
    motion_limits = drivetrain.motion_limits(drivetrain_model)
    max_linear_velocity = motion_limits.get('max_linear_velocity_meters_per_second')
    max_wheel_speed = (
        max_linear_velocity / wheel_radius if max_linear_velocity is not None else None)
    collision_guarded = machine.platform.collision_guarded and depth_camera is not None

    robot_state_publisher(
        urdf_path,
        node_name='robot_state_publisher',
        anonymous=False,
        remaps=TF_REMAPS,
    )
    motor_driver(machine, drivetrain_model, max_wheel_speed, wheel_radius)
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
            'robot_boot', 'rc_teleop.launch.py',
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
            cloud_topic=f'sensors/{depth_camera.name}/depth/points')


def arm(bl, machine):
    include(
        'robot_manipulation', ARM_LAUNCH_FILES[machine.arm.model],
        description_package=machine.arm.description_package,
        moveit_package=machine.arm.moveit_package,
        moveit_robot_name=machine.arm.moveit_robot_name,
        gripper=machine.arm.gripper,
        motions_file=bl.find('robot_machines', 'motions.yaml', subdir=machine.name),
    )


def camera_driver(bl, camera, point_cloud):
    if camera.model == 'oak_d_pro_w_poe':
        include(
            'robot_boot', 'oak_d_pro_w_poe.launch.py',
            camera=camera.name,
            detects_on_camera=camera.detects_on_camera,
            model_path=bl.find('robot_perception', 'yolov8n_coco_640x352.blob'),
            **camera.parameters,
        )
    elif camera.model == 'oak_d_sr':
        include(
            'robot_boot', 'oak_d_sr.launch.py',
            camera=camera.name,
            point_cloud=point_cloud,
            **camera.parameters,
        )
    elif camera.model == ORBBEC_CAMERA_MODEL:
        include(
            'robot_boot', 'orbbec_gemini_335l.launch.py',
            camera=camera.name,
            point_cloud=point_cloud,
            **camera.parameters,
        )
    elif camera.model == ZED_CAMERA_MODEL:
        x, y, z = camera.xyz
        roll, pitch, yaw = camera.rpy
        include(
            'robot_boot', 'zed_camera.launch.py',
            camera=camera.name,
            parent_frame=camera.parent,
            x=x, y=y, z=z, roll=roll, pitch=pitch, yaw=yaw,
            overrides_file=parameter_overrides_file({camera.name: camera.parameters}),
        )
    else:
        raise RuntimeError(f'{camera.name} has no launch file for camera model {camera.model}')


def laserscan_settings(camera):
    if camera.publishes_compressed_color:
        return OAK_LASERSCAN_SETTINGS
    if camera.model == ZED_CAMERA_MODEL:
        point_cloud_freq = camera.parameters.get('depth', {}).get('point_cloud_freq', 10.0)
        return {'scan_time': 1.0 / point_cloud_freq}
    return {'scan_time': 1.0 / camera.parameters['depth_fps']}


def perception(machine, depth_camera, camera_height_m):
    include(
        'robot_perception', 'person_follow.launch.py',
        camera=depth_camera.name,
        image_topic=(
            f'sensors/{depth_camera.name}/color/image_raw/compressed'
            if depth_camera.publishes_compressed_color else ''),
        detects_on_camera=depth_camera.has_on_camera_detector,
        overrides_file=machine.params_file('person_follow'),
    )
    if machine.behaviors.line:
        include(
            'robot_perception', 'line_follow.launch.py',
            camera=depth_camera.name,
            overrides_file=machine.params_file('line_follow'),
        )
    for surface in FOLLOWED_SURFACES:
        if getattr(machine.behaviors, surface):
            include(
                'robot_perception', 'surface_follow.launch.py',
                surface=surface,
                camera=depth_camera.name,
                camera_height_m=camera_height_m,
                overrides_file=machine.params_file('surface_follow'),
            )
    if machine.behaviors.harvest_lane:
        include(
            'robot_perception', 'harvest_lane.launch.py',
            camera=depth_camera.name,
            camera_height_m=camera_height_m,
            camera_lateral_offset_m=float(depth_camera.xyz[1]),
            overrides_file=machine.params_file('harvest_lane'),
        )


@launch_this
def robot(name: str = '', drivetrain_model: str = ''):
    machine = load_machine(name) if name else load_machine_for_this_host()
    namespace = machine.namespace
    sensors = machine.sensors
    behaviors = machine.behaviors
    depth_camera = machine.depth_camera
    bl = BetterLaunch()
    if machine.platform:
        urdf_path = bl.find('robot_description', 'robot.urdf', subdir=f'urdf/{machine.name}')
        ground_offset_m = ground_offset(urdf_path)
    else:
        urdf_path = ''
        ground_offset_m = 0.0
    camera_height_m = float(depth_camera.xyz[2]) - ground_offset_m if depth_camera else 0.0

    os.environ['ZENOH_CONFIG_OVERRIDE'] = CLIENT_CONFIG_OVERRIDE
    ensure_router(
        bl, env={'ZENOH_CONFIG_OVERRIDE': ROUTER_CONFIG_OVERRIDE},
        attempts=120, poll_seconds=1.0)

    with bl.group(namespace) if namespace else nullcontext():
        if machine.platform:
            platform(machine, drivetrain_model, urdf_path, depth_camera)
        if machine.arm:
            arm(bl, machine)

        if behaviors.hand_gesture:
            include('robot_perception', 'hand_gesture_teleop.launch.py')
        if behaviors.weeding:
            include('robot_perception', 'weeding.launch.py')
        if behaviors.follow_nav2:
            include('robot_boot', 'nav2_person_follow.launch.py')

        if behaviors.foxglove:
            include('robot_boot', 'foxglove_bridge.launch.py')

        include('robot_boot', 'diagnostic_aggregator.launch.py')

        if sensors.gps:
            gps = sensors.gps[0]
            ntrip = gps.ntrip or {}
            include(
                'robot_boot', 'gps.launch.py',
                port=gps.parameters['port'],
                baud=gps.parameters['baud'],
                frame_id=gps.parameters['frame_id'],
                topic_prefix=f'sensors/{gps.name}',
                flash=','.join(f'{key}={value}' for key, value in gps.flash.items()),
                ntrip_mountpoint=ntrip.get('mountpoint', ''),
                ntrip_username=ntrip.get('username', ''),
            )
            include(
                'robot_boot', 'robot_localization.launch.py',
                gps_topic_prefix=f'sensors/{gps.name}')

        if sensors.imu:
            imu = sensors.imu[0]
            include(
                'robot_boot', 'imu.launch.py',
                topic_prefix=f'sensors/{imu.name}', **imu.parameters)

        for camera in machine.enabled_cameras:
            camera_driver(bl, camera, behaviors.point_cloud)
            if behaviors.point_cloud and camera.has_depth:
                include(
                    'robot_boot', 'pointcloud_to_laserscan.launch.py',
                    camera=camera.name, **laserscan_settings(camera))

        if depth_camera:
            if behaviors.point_cloud:
                include(
                    'robot_perception', 'collision_overlay.launch.py',
                    camera=depth_camera.name)
            perception(machine, depth_camera, camera_height_m)

        if behaviors.gps_navigation and sensors.gps:
            include(
                'robot_boot', 'gps_navigation.launch.py',
                namespace=namespace,
                scan_topic=f'sensors/{depth_camera.name}/scan' if depth_camera else '',
                overrides_file=machine.params_file('gps_navigation'),
            )
