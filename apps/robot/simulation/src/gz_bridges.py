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


import re

from better_launch.gazebo import GazeboBridge, spawn_image_bridge, spawn_topic_bridge
from robot_boot.launch_policy import DEFAULT_DEPTH_FRAMES_PER_SECOND, include

LUMPED_SENSOR_LINK = 'base_link'


def sensor_topic(world, model_name, link, sensor, suffix):
    return f'/world/{world}/model/{model_name}/link/{link}/sensor/{sensor}/{suffix}'


def resolve_world_name(bl, world):
    with open(bl.find('robot_simulation', f'{world}.sdf', subdir='worlds')) as file:
        match = re.search(r'<world\s+name=[\'"]([^\'"]+)[\'"]', file.read())
    return match.group(1) if match else world


class SimulationCamera:
    def __init__(self, camera):
        self.name = camera.name
        self.link = f'{camera.name}_link'
        self.has_depth = camera.parameters.get('enable_depth', False)
        self.depth_frames_per_second = camera.parameters.get(
            'depth_frames_per_second', DEFAULT_DEPTH_FRAMES_PER_SECOND)


def simulation_sensors(machine):
    sensors = machine.sensors
    cameras = [SimulationCamera(camera) for camera in machine.enabled_cameras]
    return cameras, len(sensors.imu), bool(sensors.gps)


def spawn_stream_image_bridge(image_topic, camera_name, stream, transport):
    spawn_image_bridge(
        image_topic,
        node_name=f'{camera_name}_{stream}_bridge',
        remaps={image_topic: f'sensors/{camera_name}/{stream}/image_raw'},
        params={f'sensors.{camera_name}.{stream}.image_raw.enable_pub_plugins': [
            f'image_transport/{transport}']})


def spawn_simulation_bridges(bl, machine, world, model_name, depth_scan_enabled=False):
    cameras, imu_count, has_gps = simulation_sensors(machine)
    world = resolve_world_name(bl, world)

    bridges = []

    for camera in cameras:
        camera_info_topic = sensor_topic(
            world, model_name, LUMPED_SENSOR_LINK, camera.name, 'camera_info')
        bridges.append(GazeboBridge(
            camera_info_topic, 'sensor_msgs/msg/CameraInfo', 'gz2ros',
            remaps={camera_info_topic: f'sensors/{camera.name}/color/camera_info'}))
        spawn_stream_image_bridge(
            sensor_topic(world, model_name, LUMPED_SENSOR_LINK, camera.name, 'image'),
            camera.name, 'color', 'compressed')

        if camera.has_depth:
            spawn_stream_image_bridge(
                sensor_topic(world, model_name, LUMPED_SENSOR_LINK, camera.name, 'depth_image'),
                camera.name, 'depth', 'raw')
            spawn_topic_bridge(
                GazeboBridge(
                    camera_info_topic, 'sensor_msgs/msg/CameraInfo', 'gz2ros',
                    remaps={camera_info_topic: f'sensors/{camera.name}/depth/camera_info'}),
                node_name=f'{camera.name}_depth_info_bridge')

    for index in range(imu_count):
        imu_topic = sensor_topic(world, model_name, LUMPED_SENSOR_LINK, f'imu_{index}', 'imu')
        bridges.append(GazeboBridge(
            imu_topic, 'sensor_msgs/msg/Imu', 'gz2ros',
            remaps={imu_topic: f'sensors/imu_{index}/data'}))

    if has_gps:
        navsat_topic = sensor_topic(world, model_name, LUMPED_SENSOR_LINK, 'gps', 'navsat')
        bridges.append(GazeboBridge(
            navsat_topic, 'sensor_msgs/msg/NavSatFix', 'gz2ros',
            remaps={navsat_topic: 'sensors/gps_0/fix'}))

    if bridges:
        spawn_topic_bridge(*bridges, node_name='gz_bridge')

    for camera in cameras:
        if not camera.has_depth:
            continue
        bl.node(
            package='depth_image_proc',
            executable='point_cloud_xyz_node',
            name=f'{camera.name}_depth_to_point_cloud',
            remaps={
                'image_rect': f'sensors/{camera.name}/depth/image_raw',
                'points': f'sensors/{camera.name}/depth/points',
            })
        if not depth_scan_enabled:
            continue
        include(
            'robot_boot', 'point_cloud_to_laserscan.launch.py',
            camera=camera.name,
            scan_time=1.0 / camera.depth_frames_per_second,
        )
