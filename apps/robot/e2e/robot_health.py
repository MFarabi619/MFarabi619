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
import os
from pathlib import Path
import sys
import time

import yaml

CHECK_TIMEOUT_S = 15.0


def robot_configuration():
    parser = argparse.ArgumentParser()
    parser.add_argument('robot')
    robot_name = parser.parse_args().robot
    config_path = Path(__file__).parents[1] / 'machines' / robot_name / 'robot.yaml'
    if not config_path.is_file():
        sys.exit(f'{robot_name} has no robot.yaml')
    return yaml.safe_load(config_path.read_text())


def main():
    config = robot_configuration()
    namespace = config['system']['namespace']
    hostname = config['system']['hosts'][0]['hostname']
    os.environ['ZENOH_CONFIG_OVERRIDE'] = (
        f'mode="client";connect/endpoints=["tcp/{hostname}.local:7447"]')

    import rclpy
    from rclpy.qos import DurabilityPolicy, QoSProfile, qos_profile_sensor_data
    from sensor_msgs.msg import CompressedImage
    from std_msgs.msg import String
    from tf2_msgs.msg import TFMessage

    from robot_platform_msgs.msg import Feedback

    try:
        rclpy.init()
    except Exception:
        print(f'{hostname}.local router unreachable, robot still booting?')
        sys.exit(1)
    node = rclpy.create_node('robot_health_check')
    received = {}

    def record(key):
        def callback(message):
            received[key] = message
        return callback

    latched = QoSProfile(depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL)
    node.create_subscription(
        String, f'/{namespace}/robot_description', record('urdf'), latched)
    node.create_subscription(TFMessage, f'/{namespace}/tf', record('tf'), 10)
    node.create_subscription(TFMessage, '/tf', record('bare_tf'), 10)
    node.create_subscription(
        Feedback, f'/{namespace}/platform/motors/feedback', record('motor_feedback'),
        qos_profile_sensor_data)

    required_checks = ['urdf', 'tf', 'motor_feedback']
    sensors = config.get('sensors') or {}
    has_camera = any(
        camera.get('launch_enabled', True) for camera in sensors.get('camera', []))
    if has_camera:
        required_checks.append('camera')
        node.create_subscription(
            CompressedImage,
            f'/{namespace}/sensors/camera_0/color/image_raw/compressed',
            record('camera'), qos_profile_sensor_data)

    nav2_server_states = {}
    if config.get('follow_nav2', {}).get('enabled', False):
        from lifecycle_msgs.srv import GetState

        required_checks.append('nav2_follow')
        clients = {
            server: node.create_client(
                GetState, f'/{namespace}/{server}/get_state')
            for server in ('controller_server', 'planner_server', 'bt_navigator')
        }

        def poll_nav2_states():
            for server, client in clients.items():
                if server in nav2_server_states or not client.service_is_ready():
                    continue
                future = client.call_async(GetState.Request())
                rclpy.spin_until_future_complete(node, future, timeout_sec=2.0)
                if future.done() and future.result() is not None:
                    nav2_server_states[server] = future.result().current_state.label
            if all(state == 'active' for state in nav2_server_states.values()) \
                    and len(nav2_server_states) == len(clients):
                received['nav2_follow'] = nav2_server_states

    deadline = time.monotonic() + CHECK_TIMEOUT_S
    while time.monotonic() < deadline and not all(key in received for key in required_checks):
        rclpy.spin_once(node, timeout_sec=0.2)
        if 'nav2_follow' in required_checks and 'nav2_follow' not in received:
            poll_nav2_states()

    failures = [key for key in required_checks if key not in received]
    for key in required_checks:
        print(f"{'FAIL' if key in failures else 'ok  '}  {key}")
    if 'nav2_follow' in failures and nav2_server_states:
        print(f'      nav2 states: {nav2_server_states}')
    if 'urdf' in received and '<robot' not in received['urdf'].data:
        failures.append('urdf_content')
        print('FAIL  urdf_content (robot_description is not a URDF)')
    if 'bare_tf' in received:
        failures.append('bare_tf_leak')
        print('FAIL  bare_tf_leak (transforms published on un-namespaced /tf)')
    else:
        print('ok    no bare /tf leak')

    node.destroy_node()
    rclpy.shutdown()
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
