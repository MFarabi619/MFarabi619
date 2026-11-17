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


from functools import partial
import re

from better_launch.gazebo import GazeboBridge, spawn_image_bridge, spawn_topic_bridge
from robot_boot.launch_policy import DEFAULT_DEPTH_FRAMES_PER_SECOND, include
from robot_machines.machine import STEREOLABS_ZED_MODEL

LUMPED_SENSOR_LINK = 'base_link'
GAZEBO_GPS_SENSOR = 'gps'
IMAGE_TRANSPORT_BY_STREAM = {'color': 'compressed', 'depth': 'raw'}


def sensor_topic(world_name, model_name, link, sensor, suffix):
    return f'/world/{world_name}/model/{model_name}/link/{link}/sensor/{sensor}/{suffix}'


def resolve_world_name(bl, world):
    with open(bl.find('robot_simulation', f'{world}.sdf', subdir='worlds')) as file:
        match = re.search(r'<world\s+name=[\'"]([^\'"]+)[\'"]', file.read())
    return match.group(1) if match else world


class SimulationCamera:
    def __init__(self, camera):
        self.name = camera.name
        self.is_stereolabs_zed = camera.model == STEREOLABS_ZED_MODEL
        self.has_depth = self.is_stereolabs_zed or camera.parameters.get('enable_depth', False)
        self.depth_frames_per_second = camera.parameters.get(
            'depth_frames_per_second', DEFAULT_DEPTH_FRAMES_PER_SECOND)


def simulation_sensors(machine):
    sensors = machine.sensors
    cameras = [SimulationCamera(camera) for camera in machine.enabled_cameras]
    return cameras, len(sensors.imu), [gps.name for gps in sensors.gps]


def spawn_stream_image_bridge(image_topic, camera_name, stream):
    spawn_image_bridge(
        image_topic,
        node_name=f'{camera_name}_{stream}_bridge',
        remaps={image_topic: f'sensors/{camera_name}/{stream}/image_raw'},
        params={f'sensors.{camera_name}.{stream}.image_raw.enable_pub_plugins': [
            f'image_transport/{IMAGE_TRANSPORT_BY_STREAM[stream]}']})


def camera_info_bridge(camera_info_topic, camera_name, stream):
    return GazeboBridge(
        camera_info_topic, 'sensor_msgs/msg/CameraInfo', 'gz2ros',
        remaps={camera_info_topic: f'sensors/{camera_name}/{stream}/camera_info'})


def spawn_simulation_bridges(bl, machine, world):
    cameras, imu_count, gps_names = simulation_sensors(machine)
    topic = partial(sensor_topic, resolve_world_name(bl, world), machine.name, LUMPED_SENSOR_LINK)

    bridges = []

    for camera in cameras:
        camera_info_topic = topic(camera.name, 'camera_info')
        bridges.append(camera_info_bridge(camera_info_topic, camera.name, 'color'))
        spawn_stream_image_bridge(topic(camera.name, 'image'), camera.name, 'color')

        if camera.has_depth:
            spawn_stream_image_bridge(topic(camera.name, 'depth_image'), camera.name, 'depth')
            spawn_topic_bridge(
                camera_info_bridge(camera_info_topic, camera.name, 'depth'),
                node_name=f'{camera.name}_depth_camera_info_bridge')

    for index in range(imu_count):
        imu_topic = topic(f'imu_{index}', 'imu')
        bridges.append(GazeboBridge(
            imu_topic, 'sensor_msgs/msg/Imu', 'gz2ros',
            remaps={imu_topic: f'sensors/imu_{index}/data'}))

    if gps_names:
        navsat_topic = topic(GAZEBO_GPS_SENSOR, 'navsat')
        bridges.append(GazeboBridge(
            navsat_topic, 'sensor_msgs/msg/NavSatFix', 'gz2ros',
            remaps={navsat_topic: f'sensors/{gps_names[0]}/fix'}))

    if bridges:
        spawn_topic_bridge(*bridges, node_name='gz_bridge')

    for camera in cameras:
        if camera.has_depth:
            bl.node(
                package='depth_image_proc',
                executable='point_cloud_xyz_node',
                name=f'{camera.name}_depth_to_point_cloud',
                remaps={
                    'image_rect': f'sensors/{camera.name}/depth/image_raw',
                    'points': f'sensors/{camera.name}/depth/points',
                })
        if camera.is_stereolabs_zed:
            bl.node(
                package='robot_simulation',
                executable='depth_view',
                name=f'{camera.name}_depth_view',
                remaps={
                    'depth/image_raw': f'sensors/{camera.name}/depth/image_raw',
                    'depth/image_view': f'sensors/{camera.name}/depth/image_view',
                })


def spawn_depth_laserscans(machine):
    cameras, _, _ = simulation_sensors(machine)
    for camera in cameras:
        if camera.has_depth:
            include(
                'robot_boot', 'point_cloud_to_laserscan.launch.py',
                camera=camera.name,
                scan_time=1.0 / camera.depth_frames_per_second,
            )
