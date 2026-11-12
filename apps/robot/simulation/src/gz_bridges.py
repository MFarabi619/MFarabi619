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


def spawn_simulation_bridges(bl, machine, world, model_name, depth_scan_enabled=False):
    cameras, imu_count, has_gps = simulation_sensors(machine)
    world = resolve_world_name(bl, world)

    bridges = []
    image_topics = []
    image_remaps = {}
    image_plugins = {}

    for camera in cameras:
        camera_info_topic = sensor_topic(
            world, model_name, LUMPED_SENSOR_LINK, camera.name, 'camera_info')
        bridges.append(GazeboBridge(
            camera_info_topic, 'sensor_msgs/msg/CameraInfo', 'gz2ros',
            remaps={camera_info_topic: f'sensors/{camera.name}/color/camera_info'}))

        image_topic = sensor_topic(world, model_name, LUMPED_SENSOR_LINK, camera.name, 'image')
        image_topics.append(image_topic)
        image_remaps[image_topic] = f'sensors/{camera.name}/color/image_raw'
        image_plugins[f'sensors.{camera.name}.color.image_raw.enable_pub_plugins'] = [
            'image_transport/compressed']

        if camera.has_depth:
            depth_image_topic = sensor_topic(
                world, model_name, LUMPED_SENSOR_LINK, camera.name, 'depth_image')
            image_topics.append(depth_image_topic)
            image_remaps[depth_image_topic] = f'sensors/{camera.name}/depth/image_raw'
            image_plugins[f'sensors.{camera.name}.depth.image_raw.enable_pub_plugins'] = [
                'image_transport/raw']

            points_topic = sensor_topic(
                world, model_name, LUMPED_SENSOR_LINK, camera.name, 'points')
            bridges.append(GazeboBridge(
                points_topic, 'sensor_msgs/msg/PointCloud2', 'gz2ros',
                remaps={points_topic: f'sensors/{camera.name}/depth/points_body'}))

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
    if image_topics:
        spawn_image_bridge(*image_topics, node_name='image_bridge',
                           remaps=image_remaps, params=image_plugins)

    for camera in cameras:
        if not camera.has_depth:
            continue
        bl.node(
            package='robot_perception',
            executable='point_cloud_optical_adapter',
            name=f'{camera.name}_point_cloud_optical_adapter',
            params={
                'body_point_cloud_topic': f'sensors/{camera.name}/depth/points_body',
                'optical_point_cloud_topic': f'sensors/{camera.name}/depth/points',
                'optical_frame': f'{camera.name}_color_optical_frame',
            })
        if not depth_scan_enabled:
            continue
        include(
            'robot_boot', 'point_cloud_to_laserscan.launch.py',
            camera=camera.name,
            scan_time=1.0 / camera.depth_frames_per_second,
        )
