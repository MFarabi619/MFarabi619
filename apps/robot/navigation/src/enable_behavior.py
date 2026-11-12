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
import sys

from ament_index_python.packages import get_package_share_directory
import rclpy
from rcl_interfaces.srv import SetParameters
from rclpy.parameter import Parameter
from robot_boot.zenoh_router import connect_to_zenoh_router
from robot_machines.machine import load_machine
from std_srvs.srv import SetBool, Trigger
import yaml

SERVICE_TIMEOUT_SECONDS = 5.0
NODES_BY_BEHAVIOR = {
    'person_follow': ['person_follow'],
    'person_follow_slow': ['person_follow'],
    'nav2_person_follow': ['person_goal_bridge'],
    'line_follow': ['line_follow', 'line_detector'],
    'path_follow': ['path_follow', 'path_detector'],
    'park_path_follow': ['park_path_follow', 'park_path_detector'],
    'sidewalk_follow': ['sidewalk_follow', 'sidewalk_detector'],
    'harvest_lane': ['harvest_lane_navigator', 'canopy_detector'],
    'canopy_detector': ['canopy_detector'],
    'weeding': ['weeding_creep'],
    'hand_gesture_teleop': ['hand_gesture_detector', 'hand_gesture_teleop'],
}
RESETS_PARAMETERS_BEFORE_ENABLING = {'person_follow'}
PARAMETER_FILES_BEFORE_ENABLING = {
    'person_follow_slow': ('robot_boot', 'config/person_follow_slow.yaml', 'person_follow'),
}


def call(node, service_type, service_name, request):
    client = node.create_client(service_type, service_name)
    if not client.wait_for_service(timeout_sec=SERVICE_TIMEOUT_SECONDS):
        sys.exit(f'{service_name} is not available')
    future = client.call_async(request)
    rclpy.spin_until_future_complete(node, future, timeout_sec=SERVICE_TIMEOUT_SECONDS)
    if future.result() is None:
        sys.exit(f'{service_name} did not answer')
    return future.result()


def parameters_from_file(package, relative_path):
    path = f'{get_package_share_directory(package)}/{relative_path}'
    with open(path) as file:
        parameters = yaml.safe_load(file)['/**']['ros__parameters']
    return [
        Parameter(name, value=value).to_parameter_msg()
        for name, value in parameters.items()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='taro')
    parser.add_argument('--behavior', choices=sorted(NODES_BY_BEHAVIOR), required=True)
    parser.add_argument('--enabled', choices=['true', 'false'], default='true')
    arguments = parser.parse_args()
    enabled = arguments.enabled == 'true'
    namespace = load_machine(arguments.robot).namespace

    connect_to_zenoh_router(arguments.robot)
    rclpy.init()
    node = rclpy.create_node('enable_behavior')
    try:
        if enabled and arguments.behavior in RESETS_PARAMETERS_BEFORE_ENABLING:
            call(node, Trigger, f'/{namespace}/person_follow/reset_parameters',
                 Trigger.Request())
        if enabled and arguments.behavior in PARAMETER_FILES_BEFORE_ENABLING:
            package, relative_path, node_name = (
                PARAMETER_FILES_BEFORE_ENABLING[arguments.behavior])
            call(node, SetParameters, f'/{namespace}/{node_name}/set_parameters',
                 SetParameters.Request(
                     parameters=parameters_from_file(package, relative_path)))
        for node_name in NODES_BY_BEHAVIOR[arguments.behavior]:
            response = call(node, SetBool, f'/{namespace}/{node_name}/enable',
                            SetBool.Request(data=enabled))
            print(f'{node_name}: {response.message}')
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
