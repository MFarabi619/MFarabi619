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
import socket
import time

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher
import yaml

ZENOH_ROUTER_PORT = 7447
CLIENT_CONFIG_OVERRIDE = 'mode="client"'
ROUTER_CONFIG_OVERRIDE = 'mode="router"'
PIXI = os.path.expanduser('~/.pixi/bin/pixi')
JAZZY_ENV = os.path.abspath('.pixi/envs/jazzy')

GPS_TOPICS = ['fix', 'vel', 'time_reference', 'heading']

CONTROL_PARAM_FILES = [
    'apps/robot/control/config/control.yaml',
    'apps/robot/control/config/drivetrain.generated.yaml',
]

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
    robots_path = 'apps/robot/config/robots'
    for robot_name in sorted(os.listdir(robots_path)):
        config_path = os.path.join(robots_path, robot_name, 'robot.yaml')
        if not os.path.isfile(config_path):
            continue
        with open(config_path) as file:
            config = yaml.safe_load(file)
        for host in config['system']['hosts']:
            if host['hostname'] == hostname:
                return robot_name, config
    raise RuntimeError(f'no robot.yaml lists hostname {hostname}')


@launch_this
def robot():
    robot_name, robot_config = robot_identity()
    sensors = robot_config.get('sensors') or {}
    drivetrain = robot_config['platform']['drivetrain']
    with open('apps/robot/control/config/drivetrain.generated.yaml') as file:
        wheel_radius = yaml.safe_load(
            file)['diff_drive_controller']['ros__parameters']['wheel_radius']

    bl = BetterLaunch()

    bl.process(
        'ros2 run rmw_zenoh_cpp rmw_zenohd',
        name='zenoh_router',
        env={'ZENOH_CONFIG_OVERRIDE': ROUTER_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    os.environ['ZENOH_CONFIG_OVERRIDE'] = CLIENT_CONFIG_OVERRIDE
    wait_for_router()

    with open(f'apps/robot/description/urdf/{robot_name}/robot.urdf') as file:
        robot_description = file.read()
    robot_state_publisher(
        robot_description,
        node_name='robot_state_publisher',
        anonymous=False,
    )

    bl.node(
        package='robot_drivers',
        executable='pwm_dir_motor_driver',
        params={
            'gpio_chip': drivetrain['gpio_chip'],
            'pwm_frequency_hz': drivetrain['pwm_frequency_hz'],
            'max_wheel_speed': drivetrain['max_linear_velocity_mps'] / wheel_radius,
            'left_pwm_chip': drivetrain['left']['pwm_chip'],
            'left_pwm_channel': drivetrain['left']['pwm_channel'],
            'left_dir_pin': drivetrain['left']['dir_pin'],
            'left_forward_level': drivetrain['left']['forward_level'],
            'right_pwm_chip': drivetrain['right']['pwm_chip'],
            'right_pwm_channel': drivetrain['right']['pwm_channel'],
            'right_dir_pin': drivetrain['right']['dir_pin'],
            'right_forward_level': drivetrain['right']['forward_level'],
        },
        max_respawns=-1,
        respawn_delay=2.0,
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
                '--param-file', 'apps/robot/control/config/control.yaml',
                '--param-file', 'apps/robot/control/config/drivetrain.generated.yaml',
                '--controller-manager-timeout', '60',
                '--controller-ros-args', '-r ~/cmd_vel:=/platform/cmd_vel',
            ],
        )

    bl.node(
        package='controller_manager',
        executable='ros2_control_node',
        name='controller_manager',
        remaps={'~/robot_description': '/robot_description'},
        param_files=CONTROL_PARAM_FILES,
        remap_qualifier='controller_manager',
        max_respawns=-1,
        respawn_delay=2.0,
        on_exit=spawn_controllers,
    )
    spawn_controllers()

    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        remaps={'cmd_vel_out': '/platform/cmd_vel'},
        param_files=['apps/robot/control/config/twist_mux.yaml'],
        max_respawns=-1,
        respawn_delay=2.0,
    )

    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={
            'send_buffer_limit': 20000000,
            'max_qos_depth': 5,
            'best_effort_qos_topic_whitelist': ['/sensors/camera_0/.*'],
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )

    bl.node(
        package='diagnostic_aggregator',
        executable='aggregator_node',
        name='diagnostic_aggregator',
        param_files=['apps/robot/diagnostics/config/diagnostic_aggregator.yaml'],
        max_respawns=-1,
        respawn_delay=2.0,
    )

    if sensors.get('gps'):
        gps_remaps = ' '.join(f'-r {topic}:=sensors/gps_0/{topic}' for topic in GPS_TOPICS)
        bl.process(
            f'{PIXI} run --clean-env -e jazzy'
            f' {JAZZY_ENV}/bin/python'
            f' {JAZZY_ENV}/lib/nmea_navsat_driver/nmea_serial_driver'
            f' --ros-args -r __node:=nmea_navsat_driver {gps_remaps}'
            ' --params-file apps/robot/bringup/config/generated/'
            f'{robot_name}/nmea_navsat_driver.yaml',
            name='nmea_navsat_driver',
            env={'HOME': os.environ['HOME']},
            isolate_env=True,
            max_respawns=-1,
            respawn_delay=2.0,
        )

    if sensors.get('imu'):
        bl.node(
            package='robot_sensors',
            executable='imu',
            name='imu_0',
            remaps={topic: f'/sensors/imu_0/{topic}' for topic in IMU_TOPICS},
            param_files=[f'apps/robot/bringup/config/generated/{robot_name}/imu_0.yaml'],
            max_respawns=-1,
            respawn_delay=2.0,
        )

    orbbec_camera = next(
        (camera for camera in sensors.get('camera', [])
         if camera['model'] == 'orbbec_gemini_335l'
         and camera.get('launch_enabled', True)),
        None)
    if orbbec_camera:
        camera_parameters = next(iter(orbbec_camera['ros_parameters'].values()))
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
                'color/image_raw/compressed':
                    '/sensors/camera_0/color/image_raw/compressed',
                'color/camera_info': '/sensors/camera_0/color/camera_info',
                'depth/image_raw': '/sensors/camera_0/depth/image_raw',
                'depth/camera_info': '/sensors/camera_0/depth/camera_info',
            },
            max_respawns=-1,
            respawn_delay=2.0,
        )
        bl.node(
            package='robot_perception',
            executable='cone_detector',
            name='cone_detector',
            remaps={'detections': '/perception/cones'},
            max_respawns=-1,
            respawn_delay=2.0,
        )
        bl.node(
            package='robot_perception',
            executable='approach',
            name='approach',
            remaps={'detections': '/perception/cones'},
            max_respawns=-1,
            respawn_delay=2.0,
        )
        if camera_parameters['enable_depth']:
            bl.node(
                package='depth_image_proc',
                executable='point_cloud_xyz_node',
                name='depth_to_pointcloud',
                remaps={
                    'image_rect': '/sensors/camera_0/depth/image_raw',
                    'camera_info': '/sensors/camera_0/depth/camera_info',
                    'points': '/sensors/camera_0/depth/points',
                },
                max_respawns=-1,
                respawn_delay=2.0,
            )
            bl.node(
                package='pointcloud_to_laserscan',
                executable='pointcloud_to_laserscan_node',
                name='pointcloud_to_laserscan',
                remaps={
                    'cloud_in': '/sensors/camera_0/depth/points',
                    'scan': '/sensors/camera_0/scan',
                },
                params={
                    'target_frame': 'base_link',
                    'min_height': 0.15,
                    'max_height': 0.5,
                    'range_min': 0.25,
                    'range_max': 8.0,
                    'scan_time': 1.0 / camera_parameters['depth_fps'],
                },
                max_respawns=-1,
                respawn_delay=2.0,
            )
