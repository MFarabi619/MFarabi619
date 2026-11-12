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
from robot_boot.launch_policy import include

LUMPED_SENSOR_LINK = 'base_link'
SCAN_DEFAULT_DEPTH_FPS = 15


def sensor_topic(world, model, link, sensor, suffix):
    return f'/world/{world}/model/{model}/link/{link}/sensor/{sensor}/{suffix}'


def resolve_world_name(bl, world):
    with open(bl.find('robot_simulator', f'{world}.sdf', subdir='worlds')) as world_file:
        match = re.search(r'<world\s+name=[\'"]([^\'"]+)[\'"]', world_file.read())
    return match.group(1) if match else world


class SimCamera:
    def __init__(self, camera):
        self.name = camera.name
        self.link = f'{camera.name}_link'
        self.has_depth = camera.parameters.get('enable_depth', False)
        self.depth_fps = camera.parameters.get('depth_fps', SCAN_DEFAULT_DEPTH_FPS)


def sim_sensors(machine):
    sensors = machine.sensors
    cameras = [SimCamera(camera) for camera in machine.enabled_cameras]
    return cameras, len(sensors.imu), bool(sensors.gps)


def spawn_sim_bridges(bl, machine, world, model, depth_scan=False):
    cameras, imu_count, has_gps = sim_sensors(machine)
    world = resolve_world_name(bl, world)

    bridges = []
    image_topics = []
    image_remaps = {}
    image_plugins = {}

    for camera in cameras:
        info = sensor_topic(world, model, LUMPED_SENSOR_LINK, camera.name, 'camera_info')
        bridges.append(GazeboBridge(
            info, 'sensor_msgs/msg/CameraInfo', 'gz2ros',
            remaps={info: f'sensors/{camera.name}/color/camera_info'}))

        image = sensor_topic(world, model, LUMPED_SENSOR_LINK, camera.name, 'image')
        image_topics.append(image)
        image_remaps[image] = f'sensors/{camera.name}/color/image_raw'
        image_plugins[f'sensors.{camera.name}.color.image_raw.enable_pub_plugins'] = [
            'image_transport/compressed']

        if camera.has_depth:
            depth = sensor_topic(world, model, LUMPED_SENSOR_LINK, camera.name, 'depth_image')
            image_topics.append(depth)
            image_remaps[depth] = f'sensors/{camera.name}/depth/image_raw'
            image_plugins[f'sensors.{camera.name}.depth.image_raw.enable_pub_plugins'] = [
                'image_transport/raw']

            points = sensor_topic(world, model, LUMPED_SENSOR_LINK, camera.name, 'points')
            bridges.append(GazeboBridge(
                points, 'sensor_msgs/msg/PointCloud2', 'gz2ros',
                remaps={points: f'sensors/{camera.name}/depth/points_body'}))

    for index in range(imu_count):
        imu = sensor_topic(world, model, LUMPED_SENSOR_LINK, f'imu_{index}', 'imu')
        bridges.append(GazeboBridge(
            imu, 'sensor_msgs/msg/Imu', 'gz2ros',
            remaps={imu: f'sensors/imu_{index}/data'}))

    if has_gps:
        navsat = sensor_topic(world, model, LUMPED_SENSOR_LINK, 'gps', 'navsat')
        bridges.append(GazeboBridge(
            navsat, 'sensor_msgs/msg/NavSatFix', 'gz2ros',
            remaps={navsat: 'sensors/gps_0/fix'}))

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
            executable='cloud_optical_adapter',
            name=f'{camera.name}_cloud_optical_adapter',
            params={
                'body_cloud_topic': f'sensors/{camera.name}/depth/points_body',
                'optical_cloud_topic': f'sensors/{camera.name}/depth/points',
                'optical_frame': f'{camera.name}_color_optical_frame',
            })
        if not depth_scan:
            continue
        include(
            'robot_boot', 'pointcloud_to_laserscan.launch.py',
            camera=camera.name,
            scan_time=1.0 / camera.depth_fps,
        )
