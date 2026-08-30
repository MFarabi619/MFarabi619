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
from pathlib import Path
import socket
import tempfile
import time
import xml.etree.ElementTree as ElementTree

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher
import yaml

ZENOH_ROUTER_PORT = 7447
CLIENT_CONFIG_OVERRIDE = 'mode="client"'
ROUTER_CONFIG_OVERRIDE = 'mode="router"'
PIXI = os.path.expanduser('~/.pixi/bin/pixi')
JAZZY_ENV = os.path.abspath('.pixi/envs/jazzy')
RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}
FOLLOWED_SURFACES = {
    'sidewalk': {'surface_class_ids': [2, 3]},
    'park_path': {'surface_class_ids': [1, 2, 3]},
    'path': {
        'mask_source': 'brightness',
        'max_saturation': 0.75,
        'max_value': 0.35,
        'roi_top_fraction': 0.6,
        'min_fraction': 0.6,
        'max_detections_per_second': 15.0,
    },
}
TF_REMAPS = {'/tf': 'tf', '/tf_static': 'tf_static'}

GPS_TOPICS = ['fix', 'vel', 'time_reference', 'heading']

def ground_offset(urdf_path):
    robot = ElementTree.parse(urdf_path).getroot()
    for joint in robot.iter('joint'):
        child = joint.find('child')
        if child is None or child.get('link') != 'base_footprint':
            continue
        origin = joint.find('origin')
        if origin is None:
            break
        return float(origin.get('xyz', '0 0 0').split()[2])
    return 0.0


def wheel_geometry(urdf_path):
    robot = ElementTree.parse(urdf_path).getroot()
    joint_by_child = {}
    for joint in robot.iter('joint'):
        parent = joint.find('parent')
        if parent is None:
            continue
        origin = joint.find('origin')
        xyz = origin.get('xyz', '0 0 0') if origin is not None else '0 0 0'
        rpy = origin.get('rpy', '0 0 0') if origin is not None else '0 0 0'
        joint_by_child[joint.find('child').get('link')] = (
            parent.get('link'), float(xyz.split()[1]),
            any(float(angle) != 0.0 for angle in rpy.split()), joint.get('name'))

    def lateral_offset(link):
        offset = 0.0
        while link in joint_by_child:
            link, y, is_rotated, joint_name = joint_by_child[link]
            if is_rotated:
                raise RuntimeError(
                    f'{joint_name} has a rotated origin;'
                    ' wheel_geometry only handles pure-translation wheel chains')
            offset += y
        return offset

    wheel_separation = abs(
        lateral_offset('rear_left_wheel_link')
        - lateral_offset('rear_right_wheel_link'))

    radii = {
        float(cylinder.get('radius'))
        for link in robot.iter('link')
        if link.get('name').endswith('_wheel_link')
        for cylinder in link.find('collision').iter('cylinder')
    }
    if len(radii) != 1:
        raise RuntimeError(f'expected one wheel collision radius, found {radii}')
    return wheel_separation, radii.pop()


def write_drivetrain_parameters(wheel_separation, wheel_radius):
    parameters = {
        '/**/diff_drive_controller': {
            'ros__parameters': {
                'wheel_separation': wheel_separation,
                'wheel_radius': wheel_radius,
            },
        },
    }
    parameters_file = tempfile.NamedTemporaryFile(
        mode='w', prefix='drivetrain_', suffix='.yaml', delete=False)
    yaml.safe_dump(parameters, parameters_file)
    parameters_file.close()
    return parameters_file.name

IMU_TOPICS = [
    'data', 'mag', 'linear_acceleration', 'stability',
    'activity', 'steps', 'shake', 'calibration_status',
]


def wait_for_router(attempts=120):
    for _ in range(attempts):
        try:
            socket.create_connection(
                ('127.0.0.1', ZENOH_ROUTER_PORT), timeout=0.5).close()
            return
        except OSError:
            time.sleep(1.0)


def robot_identity():
    hostname = socket.gethostname()
    for config_path in sorted(Path('machines').glob('*/robot.yaml')):
        config = yaml.safe_load(config_path.read_text())
        for host in config['system']['hosts']:
            if host['hostname'] == hostname:
                return config_path.parent.name, config
    raise RuntimeError(f'no robot.yaml lists hostname {hostname}')


def board_pins(robot_config):
    board = robot_config['system']['hosts'][0]['board']
    with open(f'elec/boards/{board}.yaml') as file:
        return yaml.safe_load(file)['pins']


def resolve_line(pins, pin):
    entry = pins[pin]
    return entry['gpio_chip'], entry['line']


def resolve_pwm(pins, pin):
    entry = pins[pin]
    return entry['pwm_chip'], entry['pwm_channel']


@launch_this
def robot():
    robot_name, robot_config = robot_identity()
    if robot_config.get('version', 0) < 1:
        raise RuntimeError(
            f'{robot_name} robot.yaml is schema version 0; wiring is now header'
            ' pins resolved through elec/boards/ (version 1)')
    namespace = robot_config['system']['namespace']
    sensors = robot_config.get('sensors') or {}
    drivetrain = robot_config['platform']['drivetrain']
    rc_receiver = robot_config['platform'].get('rc_receiver')
    if rc_receiver and not rc_receiver.get('launch_enabled', True):
        rc_receiver = None
    drivetrain_model = drivetrain.get('model', 'pwm_dir')
    wheel_separation, wheel_radius = wheel_geometry(
        f'mech/urdf/{robot_name}/robot.urdf')
    drivetrain_parameters_path = write_drivetrain_parameters(
        wheel_separation, wheel_radius)

    oak_d_camera_config = next(
        (camera for camera in sensors.get('camera', [])
         if camera['model'] in ('oak_d_sr', 'oak_d_pro_w_poe')
         and camera.get('launch_enabled', True)),
        None)
    orbbec_gemini_335l_camera_config = next(
        (camera for camera in sensors.get('camera', [])
         if camera['model'] == 'orbbec_gemini_335l'
         and camera.get('launch_enabled', True)),
        None)
    if oak_d_camera_config:
        depth_camera_name = next(iter(oak_d_camera_config['ros_parameters']))
    elif orbbec_gemini_335l_camera_config and next(
            iter(orbbec_gemini_335l_camera_config['ros_parameters'].values()))['enable_depth']:
        depth_camera_name = 'camera_0'
    else:
        depth_camera_name = None
    depth_camera_config = oak_d_camera_config or orbbec_gemini_335l_camera_config
    camera_mount_xyz = (
        depth_camera_config.get('xyz', [0.0, 0.0, 0.0])
        if depth_camera_config else [0.0, 0.0, 0.0])
    # The depth cloud, the scan derived from it and the collision overlay all
    # read every depth frame. Nothing needs them unless navigation or mapping is
    # running, and on a loaded robot they starve the detector that does.
    depth_cloud_enabled = robot_config.get('depth_cloud', {}).get('enabled', True)
    camera_height_m = float(camera_mount_xyz[2]) - ground_offset(
        f'mech/urdf/{robot_name}/robot.urdf')
    collision_monitor_binary = f'{JAZZY_ENV}/lib/nav2_collision_monitor/collision_monitor'
    collision_guarded = (
        robot_config['platform'].get('collision_guarded', False)
        and depth_camera_name is not None)
    detects_on_camera = bool(
        oak_d_camera_config
        and oak_d_camera_config['model'] == 'oak_d_pro_w_poe'
        and oak_d_camera_config.get('detects_on_camera', False))

    bl = BetterLaunch()

    bl.process(
        'ros2 run rmw_zenoh_cpp rmw_zenohd',
        name='zenoh_router',
        env={'ZENOH_CONFIG_OVERRIDE': ROUTER_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    os.environ['ZENOH_CONFIG_OVERRIDE'] = CLIENT_CONFIG_OVERRIDE
    wait_for_router()

    with bl.group(namespace):
        robot_state_publisher(
            os.path.abspath(f'mech/urdf/{robot_name}/robot.urdf'),
            node_name='robot_state_publisher',
            anonymous=False,
            remaps=TF_REMAPS,
        )

        if drivetrain_model == 'odrive_usb':
            bl.node(
                package='robot_drivers',
                executable='odrive_motor_driver',
                params={
                    'gear_ratio': drivetrain['gear_ratio'],
                    'max_wheel_speed': drivetrain['max_linear_velocity_mps'] / wheel_radius,
                    'left_serial': drivetrain['left']['serial'],
                    'left_reversed': drivetrain['left']['reversed'],
                    'right_serial': drivetrain['right']['serial'],
                    'right_reversed': drivetrain['right']['reversed'],
                },
                **RESPAWN,
            )
        elif drivetrain_model == 'svd48v':
            bl.node(
                package='robot_drivers',
                executable='svd48v_motor_driver',
                params={
                    'serial_port': drivetrain['serial_port'],
                    'baud_rate': drivetrain['baud_rate'],
                    'max_wheel_speed': drivetrain['max_linear_velocity_mps'] / wheel_radius,
                    'acceleration_rpm_per_second': drivetrain['acceleration_rpm_per_second'],
                    'speed_smoothing_time': drivetrain['speed_smoothing_time'],
                    'left_reversed': drivetrain['left']['reversed'],
                    'right_reversed': drivetrain['right']['reversed'],
                },
                **RESPAWN,
            )
        elif drivetrain_model == 'mock':
            pass
        elif drivetrain_model == 'rc_pulse':
            pins = board_pins(robot_config)
            left_pwm_chip, left_pwm_channel = resolve_pwm(pins, drivetrain['left']['pwm_pin'])
            right_pwm_chip, right_pwm_channel = resolve_pwm(pins, drivetrain['right']['pwm_pin'])
            bl.node(
                package='robot_drivers',
                executable='rc_pulse_motor_driver',
                params={
                    'max_wheel_speed': drivetrain['max_linear_velocity_mps'] / wheel_radius,
                    'left_pwm_chip': left_pwm_chip,
                    'left_pwm_channel': left_pwm_channel,
                    'left_reversed': drivetrain['left']['reversed'],
                    'right_pwm_chip': right_pwm_chip,
                    'right_pwm_channel': right_pwm_channel,
                    'right_reversed': drivetrain['right']['reversed'],
                },
                **RESPAWN,
            )
        else:
            pins = board_pins(robot_config)
            left_pwm_chip, left_pwm_channel = resolve_pwm(pins, drivetrain['left']['pwm_pin'])
            right_pwm_chip, right_pwm_channel = resolve_pwm(pins, drivetrain['right']['pwm_pin'])
            left_dir_chip, left_dir_line = resolve_line(pins, drivetrain['left']['dir_pin'])
            right_dir_chip, right_dir_line = resolve_line(pins, drivetrain['right']['dir_pin'])
            if left_dir_chip != right_dir_chip:
                raise RuntimeError('left and right direction pins must share one gpio chip')
            bl.node(
                package='robot_drivers',
                executable='pwm_dir_motor_driver',
                params={
                    'gpio_chip': left_dir_chip,
                    'pwm_frequency_hz': drivetrain['pwm_frequency_hz'],
                    'max_wheel_speed': drivetrain['max_linear_velocity_mps'] / wheel_radius,
                    'min_duty': drivetrain.get('min_duty', 0.0),
                    'left_pwm_chip': left_pwm_chip,
                    'left_pwm_channel': left_pwm_channel,
                    'left_dir_line': left_dir_line,
                    'left_forward_level': drivetrain['left']['forward_level'],
                    'right_pwm_chip': right_pwm_chip,
                    'right_pwm_channel': right_pwm_channel,
                    'right_dir_line': right_dir_line,
                    'right_forward_level': drivetrain['right']['forward_level'],
                },
                **RESPAWN,
            )

        def spawn_controllers():
            if bl.is_shutdown:
                return
            bl.node(
                package='controller_manager',
                executable='spawner',
                name='controller_spawner',
                cmd_args=[
                    'joint_state_broadcaster', 'diff_drive_controller',
                    '--param-file', 'control/config/control.yaml',
                    '--param-file', drivetrain_parameters_path,
                    '--controller-manager-timeout', '60',
                    '--controller-ros-args',
                    '-r ~/cmd_vel:=platform/cmd_vel -r /tf:=tf -r /tf_static:=tf_static',
                ],
            )

        bl.node(
            package='controller_manager',
            executable='ros2_control_node',
            name='controller_manager',
            remaps={'~/robot_description': 'robot_description'},
            param_files=[
                'control/config/control.yaml', drivetrain_parameters_path],
            remap_qualifier='controller_manager',
            **RESPAWN,
            on_exit=spawn_controllers,
        )
        spawn_controllers()

        if rc_receiver:
            pins = board_pins(robot_config)
            channel_1_chip, channel_1_line = resolve_line(pins, rc_receiver['channel_1_pin'])
            channel_2_chip, channel_2_line = resolve_line(pins, rc_receiver['channel_2_pin'])
            if channel_1_chip != channel_2_chip:
                raise RuntimeError('rc channel pins must share one gpio chip')
            bl.node(
                package='robot_drivers',
                executable='rc_receiver_joy',
                name='rc_receiver_joy',
                params={
                    'gpio_chip': channel_1_chip,
                    'channel_1_line': channel_1_line,
                    'channel_2_line': channel_2_line,
                    'tank_mixed': rc_receiver.get('tank_mixed', False),
                },
                remaps={'joy': 'joy_teleop/joy'},
                **RESPAWN,
            )
            bl.node(
                package='teleop_twist_joy',
                executable='teleop_node',
                name='rc_teleop',
                param_files=['boot/config/rc_teleop.yaml'],
                remaps={
                    'joy': 'joy_teleop/joy',
                    'cmd_vel': 'joy_teleop/cmd_vel',
                },
                **RESPAWN,
            )

        bl.node(
            package='twist_mux',
            executable='twist_mux',
            name='twist_mux',
            remaps={
                'cmd_vel_out': ('platform/cmd_vel_raw' if collision_guarded
                                else 'platform/cmd_vel'),
            },
            param_files=['control/config/twist_mux.yaml'],
            **RESPAWN,
        )

        if collision_guarded:
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' {collision_monitor_binary}'
                ' --ros-args'
                f' -r __ns:=/{namespace}'
                ' -r /tf:=tf -r /tf_static:=tf_static'
                ' --params-file control/config/collision_monitor.yaml'
                f' -p scan.topic:=sensors/{depth_camera_name}/scan',
                name='collision_monitor',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' {JAZZY_ENV}/lib/nav2_lifecycle_manager/lifecycle_manager'
                ' --ros-args -r __node:=collision_lifecycle_manager'
                f' -r __ns:=/{namespace}'
                ' --params-file control/config/collision_monitor.yaml',
                name='collision_lifecycle_manager',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )

        if robot_config.get('hand_gesture', {}).get('enabled', False):
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' python {os.path.abspath("perception/src/hand_gesture_detector.py")}'
                ' --ros-args'
                f' -r __ns:=/{namespace}'
                ' -p image_topic:=sensors/camera_0/color/image_raw/compressed'
                ' -p start_enabled:=false'
                ' -p num_hands:=2'
                ' -p min_hand_detection_confidence:=0.4'
                ' -r /joy_teleop/cmd_vel:=joy_teleop/cmd_vel',
                name='hand_gesture_detector',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )
            bl.node(
                package='robot_perception',
                executable='hand_gesture_teleop',
                name='hand_gesture_teleop',
                params={'start_enabled': False},
                remaps={'/joy_teleop/cmd_vel': 'joy_teleop/cmd_vel'},
                **RESPAWN,
            )
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' python {os.path.abspath("perception/src/weeding_creep.py")}'
                ' --ros-args'
                f' -r __ns:=/{namespace}'
                ' -r /tf:=tf -r /tf_static:=tf_static'
                ' -p start_enabled:=false',
                name='weeding_creep',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )

        if robot_config.get('follow_nav2', {}).get('enabled', False):
            follow_parameters = os.path.abspath('navigation/config/follow.yaml')
            follow_point_tree = os.path.abspath('navigation/config/follow_point.xml')
            for package, server in (
                    ('nav2_controller', 'controller_server'),
                    ('nav2_planner', 'planner_server'),
                    ('nav2_bt_navigator', 'bt_navigator')):
                tree_argument = (
                    f' -p default_nav_to_pose_bt_xml:={follow_point_tree}'
                    if server == 'bt_navigator' else '')
                bl.process(
                    f'{PIXI} run --clean-env -e jazzy'
                    f' {JAZZY_ENV}/lib/{package}/{server}'
                    ' --ros-args'
                    f' -r __ns:=/{namespace}'
                    ' -r /tf:=tf -r /tf_static:=tf_static'
                    f' --params-file {follow_parameters}'
                    f'{tree_argument}',
                    name=server,
                    env={'HOME': os.environ['HOME']},
                    isolate_env=True,
                    **RESPAWN,
                )
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' python {os.path.abspath("perception/src/person_goal_bridge.py")}'
                ' --ros-args'
                f' -r __ns:=/{namespace}'
                ' -r /tf:=tf -r /tf_static:=tf_static',
                name='person_goal_bridge',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' {JAZZY_ENV}/lib/nav2_lifecycle_manager/lifecycle_manager'
                ' --ros-args -r __node:=follow_lifecycle_manager'
                f' -r __ns:=/{namespace}'
                f' --params-file {follow_parameters}',
                name='follow_lifecycle_manager',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
            )

        if robot_config.get('foxglove', {}).get('enabled', True):
            bl.node(
                package='foxglove_bridge',
                executable='foxglove_bridge',
                name='foxglove_bridge',
                params={
                    'send_buffer_limit': 20000000,
                    'max_qos_depth': 5,
                    'best_effort_qos_topic_whitelist': [
                        f'/{namespace}/sensors/camera_[0-9]+/.*',
                    ],
                    'topic_whitelist': [
                        f'/{namespace}/sensors/camera_[0-9]+/(color|depth)/image_raw/(compressed|compressedDepth)$',
                        f'/{namespace}/sensors/camera_[0-9]+/(color|depth)/camera_info$',
                        f'/{namespace}/sensors/camera_[0-9]+/depth/points$',
                        f'/{namespace}/sensors/camera_[0-9]+/scan$',
                        f'/{namespace}/sensors/(gps|imu)_[0-9]+/.*',
                        f'/{namespace}/perception/.*',
                        f'/{namespace}/platform/.*',
                        f'/{namespace}/joy_teleop/cmd_vel$',
                        f'/{namespace}/tf(_static)?$',
                        f'/{namespace}/map$',
                        f'/{namespace}/local_costmap/costmap$',
                        f'/{namespace}/plan$',
                        f'/{namespace}/slam_toolbox/.*',
                        f'/{namespace}/diagnostics.*',
                        f'/{namespace}/robot_description$',
                    ],
                },
                **RESPAWN,
            )

        bl.node(
            package='diagnostic_aggregator',
            executable='aggregator_node',
            name='diagnostic_aggregator',
            param_files=['boot/config/diagnostic_aggregator.yaml'],
            **RESPAWN,
        )

        if sensors.get('gps'):
            gps_remap_args = ' '.join(
                f'-r {topic}:=sensors/gps_0/{topic}' for topic in GPS_TOPICS)
            gps_parameters = next(iter(sensors['gps'][0]['ros_parameters'].values()))
            gps_parameter_args = ' '.join(
                f'-p {name}:={value}' for name, value in gps_parameters.items())
            bl.process(
                f'{PIXI} run --clean-env -e jazzy'
                f' {JAZZY_ENV}/bin/python'
                f' {JAZZY_ENV}/lib/nmea_navsat_driver/nmea_serial_driver'
                f' --ros-args -r __node:=nmea_navsat_driver'
                f' -r __ns:=/{namespace} {gps_remap_args} {gps_parameter_args}',
                name='nmea_navsat_driver',
                env={'HOME': os.environ['HOME']},
                isolate_env=True,
                **RESPAWN,
            )

        if sensors.get('imu'):
            bl.node(
                package='robot_drivers',
                executable='imu',
                name='imu_0',
                remaps={topic: f'sensors/imu_0/{topic}' for topic in IMU_TOPICS},
                params=next(iter(sensors['imu'][0]['ros_parameters'].values())),
                **RESPAWN,
            )

        if oak_d_camera_config:
            camera_name = next(iter(oak_d_camera_config['ros_parameters']))
            if oak_d_camera_config['model'] == 'oak_d_pro_w_poe':
                optical_frame = f'{camera_name}_link_color_optical_frame'
                oak_d_camera_driver_parameters = {
                    'frame_id': optical_frame,
                    'depth_fps': 30.0,
                    'color_fps': 60.0,
                    'jpeg_quality': 60,
                } | oak_d_camera_config['ros_parameters'][camera_name]
                if detects_on_camera:
                    oak_d_camera_driver_parameters['model_path'] = (
                        os.path.abspath(
                            'perception/models/yolov8n_coco_640x352.blob'))
            else:
                optical_frame = f'{camera_name}_link_right_camera_optical_frame'
                oak_d_camera_driver_parameters = {
                    'frame_id': optical_frame,
                    'fps': 15.0,
                    'jpeg_quality': 60,
                }
            bl.node(
                package='robot_drivers',
                executable=('oak_d_pro_w_poe_spatial' if detects_on_camera
                            else oak_d_camera_config['model']),
                name=oak_d_camera_config['model'],
                params=oak_d_camera_driver_parameters,
                remaps={
                    'color/image_raw/compressed':
                        f'sensors/{camera_name}/color/image_raw/compressed',
                    'color/camera_info': f'sensors/{camera_name}/color/camera_info',
                    'depth/image_raw': f'sensors/{camera_name}/depth/image_raw',
                    'depth/image_raw/compressed':
                        f'sensors/{camera_name}/depth/image_raw/compressed',
                    'depth/camera_info': f'sensors/{camera_name}/depth/camera_info',
                    'depth/points': f'sensors/{camera_name}/depth/points',
                    'imu/data': f'sensors/{camera_name}/imu/data',
                },
                **RESPAWN,
            )
            bl.node(
                package='tf2_ros',
                executable='static_transform_publisher',
                name='oak_d_optical_frame_bridge',
                cmd_args=[
                    '--roll', '-1.5708', '--yaw', '-1.5708',
                    '--frame-id', f'{camera_name}_link',
                    '--child-frame-id', optical_frame,
                ],
                remaps=TF_REMAPS,
                **RESPAWN,
            )
            if oak_d_camera_config['model'] == 'oak_d_sr' and depth_cloud_enabled:
                bl.node(
                    package='depth_image_proc',
                    executable='point_cloud_xyz_node',
                    name='oak_d_sr_depth_to_pointcloud',
                    remaps={
                        'image_rect': f'sensors/{camera_name}/depth/image_raw',
                        'camera_info': f'sensors/{camera_name}/depth/camera_info',
                        'points': f'sensors/{camera_name}/depth/points',
                    },
                    **RESPAWN,
                )
            if depth_cloud_enabled:
                bl.node(
                    package='pointcloud_to_laserscan',
                    executable='pointcloud_to_laserscan_node',
                    name='oak_d_pointcloud_to_laserscan',
                    remaps=TF_REMAPS | {
                        'cloud_in': f'sensors/{camera_name}/depth/points',
                        'scan': f'sensors/{camera_name}/scan',
                    },
                    # TODO: rescope range_max to the OAK-D SR's 1.5m usable depth band
                    params={
                        'target_frame': 'base_link',
                        'min_height': 0.1,
                        'max_height': 0.6,
                        'range_min': 0.2,
                        'range_max': 3.0,
                        'scan_time': 0.05,
                    },
                    **RESPAWN,
                )

        if orbbec_gemini_335l_camera_config:
            camera_parameters = next(
                iter(orbbec_gemini_335l_camera_config['ros_parameters'].values()))
            bl.node(
                package='robot_drivers',
                executable='orbbec_gemini_335l',
                name='orbbec_gemini_335l',
                params={
                    'color_width': camera_parameters['color_width'],
                    'color_height': camera_parameters['color_height'],
                    'color_fps': camera_parameters['color_fps'],
                    'enable_depth': camera_parameters['enable_depth'],
                    'depth_width': camera_parameters['depth_width'],
                    'depth_height': camera_parameters['depth_height'],
                    'depth_fps': camera_parameters['depth_fps'],
                    'depth_decimation': camera_parameters['depth_decimation'],
                },
                remaps={
                    'color/image_raw': 'sensors/camera_0/color/image_raw',
                    'color/image_raw/compressed':
                        'sensors/camera_0/color/image_raw/compressed',
                    'color/camera_info': 'sensors/camera_0/color/camera_info',
                    'depth/image_raw': 'sensors/camera_0/depth/image_raw',
                    'depth/image_raw/compressed':
                        'sensors/camera_0/depth/image_raw/compressed',
                    'depth/camera_info': 'sensors/camera_0/depth/camera_info',
                },
                **RESPAWN,
            )
            if camera_parameters['enable_depth'] and depth_cloud_enabled:
                bl.node(
                    package='depth_image_proc',
                    executable='point_cloud_xyz_node',
                    name='depth_to_pointcloud',
                    remaps={
                        'image_rect': 'sensors/camera_0/depth/image_raw',
                        'camera_info': 'sensors/camera_0/depth/camera_info',
                        'points': 'sensors/camera_0/depth/points',
                    },
                    **RESPAWN,
                )
                bl.node(
                    package='pointcloud_to_laserscan',
                    executable='pointcloud_to_laserscan_node',
                    name='pointcloud_to_laserscan',
                    remaps=TF_REMAPS | {
                        'cloud_in': 'sensors/camera_0/depth/points',
                        'scan': 'sensors/camera_0/scan',
                    },
                    params={
                        'target_frame': 'base_link',
                        'min_height': 0.1,
                        'max_height': 0.5,
                        'range_min': 0.25,
                        'range_max': 8.0,
                        'scan_time': 1.0 / camera_parameters['depth_fps'],
                    },
                    **RESPAWN,
                )
        if depth_camera_name is not None:
            if depth_cloud_enabled:
                bl.node(
                    package='robot_perception',
                    executable='collision_overlay',
                    name='collision_overlay',
                    remaps=TF_REMAPS,
                    params={
                        'cloud_topic': f'sensors/{depth_camera_name}/depth/points',
                        'camera_info_topic':
                            f'sensors/{depth_camera_name}/color/camera_info',
                        'overlay_topic': 'perception/collision/overlay',
                    },
                    **RESPAWN,
                )
            if oak_d_camera_config:
                detector_image_topic = (
                    f'sensors/{depth_camera_name}/color/image_raw/compressed')
            else:
                detector_image_topic = f'sensors/{depth_camera_name}/color/image_raw'
            if not detects_on_camera:
                bl.node(
                    package='robot_perception',
                    executable='person_detector',
                    name='person_detector',
                    params={
                        'image_topic': detector_image_topic,
                        'depth_topic': f'sensors/{depth_camera_name}/depth/image_raw',
                        'depth_camera_info_topic': f'sensors/{depth_camera_name}/depth/camera_info',
                        'min_score': 0.3,
                        'max_detections_per_second': 10.0,
                    } | robot_config.get('detector', {}),
                    **RESPAWN,
                )
            person_follow_parameters = {
                'standoff_distance': 1.5,
                'max_missing_frames': 24,
                'start_enabled': False,
                'max_forward_speed': 2.0,
                'max_angular_speed': 2.0,
                'max_backward_speed': 2.0,
                'distance_gain': 2.5,
                'distance_damping': 0.4,
                'steer_gain': 1.5,
                'steer_damping': 0.7,
                'command_smoothing_seconds': 0.1,
                'distance_deadband': 0.1,
                'steer_deadband': 0.05,
            } | robot_config.get('follow', {})
            bl.node(
                package='robot_perception',
                executable='approach',
                name='person_follow',
                params=person_follow_parameters,
                **RESPAWN,
            )

            line_config = robot_config.get('line', {})
            if line_config.get('enabled', False):
                bl.node(
                    package='robot_perception',
                    executable='color_blob_detector',
                    name='line_detector',
                    params={
                        'image_topic':
                            f'sensors/{depth_camera_name}/color/image_raw/compressed',
                        'depth_topic': f'sensors/{depth_camera_name}/depth/image_raw',
                        'depth_camera_info_topic':
                            f'sensors/{depth_camera_name}/depth/camera_info',
                        'detections_topic': 'perception/line/detections',
                        'overlay_topic': 'perception/line/overlay',
                        'class_label': 'line',
                        'hue_min': 0.0,
                        'hue_max': 180.0,
                        'min_saturation': 0.0,
                        'max_saturation': 0.25,
                        'min_value': 0.6,
                        'min_triangularity': 0.0,
                        'min_aspect_ratio': 0.0,
                        'min_area': 800,
                        'roi_top_fraction': 0.55,
                        'start_enabled': False,
                    } | line_config.get('detector', {}),
                    **RESPAWN,
                )
                bl.node(
                    package='robot_perception',
                    executable='row_follow',
                    name='line_follow',
                    params={
                        'detections_topic': 'perception/line/detections',
                        'start_enabled': False,
                    } | line_config.get('follow', {}),
                    **RESPAWN,
                )

            for surface, surface_defaults in FOLLOWED_SURFACES.items():
                surface_config = robot_config.get(surface, {})
                if not surface_config.get('enabled', False):
                    continue
                bl.node(
                    package='robot_perception',
                    executable='surface_detector',
                    name=f'{surface}_detector',
                    params={
                        'image_topic':
                            f'sensors/{depth_camera_name}/color/image_raw/compressed',
                        'detections_topic': f'perception/{surface}/detections',
                        'overlay_topic': f'perception/{surface}/overlay',
                        'class_label': surface,
                        'max_detections_per_second': 5.0,
                    } | surface_defaults | surface_config.get('detector', {}),
                    **RESPAWN,
                )
                bl.node(
                    package='robot_perception',
                    executable='surface_follow',
                    name=f'{surface}_follow',
                    params={
                        'detections_topic': f'perception/{surface}/detections',
                        'camera_info_topic':
                            f'sensors/{depth_camera_name}/color/camera_info',
                        'camera_height_m': camera_height_m,
                        'start_enabled': False,
                    } | surface_config.get('follow', {}),
                    **RESPAWN,
                )

            harvest_lane_config = robot_config.get('harvest_lane', {})
            if harvest_lane_config.get('enabled', False):
                bl.node(
                    package='robot_perception',
                    executable='canopy_detector',
                    name='canopy_detector',
                    params={
                        'image_topic':
                            f'sensors/{depth_camera_name}/color/image_raw/compressed',
                        'mask_topic': 'perception/canopy/mask/compressed',
                        'fraction_topic': 'perception/canopy/fraction',
                    } | harvest_lane_config.get('detector', {}),
                    **RESPAWN,
                )
                bl.node(
                    package='robot_perception',
                    executable='harvest_lane_navigator',
                    name='harvest_lane_navigator',
                    params={
                        'mask_topic': 'perception/canopy/mask/compressed',
                        'camera_info_topic':
                            f'sensors/{depth_camera_name}/color/camera_info',
                        'depth_topic': f'sensors/{depth_camera_name}/depth/image_raw',
                        'odom_topic': 'diff_drive_controller/odom',
                        'camera_height_m': camera_height_m,
                        'camera_lateral_offset_m': float(camera_mount_xyz[1]),
                        'start_enabled': False,
                    } | harvest_lane_config.get('navigator', {}),
                    **RESPAWN,
                )
