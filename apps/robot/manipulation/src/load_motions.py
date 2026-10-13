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

from play_motion2_msgs.msg import Motion
from play_motion2_msgs.srv import AddMotion
import rclpy
import yaml


def catalog(robot):
    with open(f'machines/{robot}/motions.yaml') as motions_file:
        return yaml.safe_load(motions_file)['/**']['ros__parameters']['motions']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='kinova-link-6')
    arguments = parser.parse_args()

    rclpy.init()
    node = rclpy.create_node('load_motions')
    client = node.create_client(AddMotion, '/play_motion2/add_motion')
    if not client.wait_for_service(timeout_sec=10.0):
        print('load_motions: /play_motion2/add_motion unavailable', flush=True)
        os._exit(1)

    failures = 0
    for key, entry in catalog(arguments.robot).items():
        motion = Motion()
        motion.key = key
        motion.joints = entry['joints']
        motion.positions = [float(value) for value in entry['positions']]
        motion.times_from_start = [
            float(value) for value in entry['times_from_start']]
        meta = entry.get('meta', {})
        motion.name = meta.get('name', key)
        motion.usage = meta.get('usage', '')
        motion.description = meta.get('description', '')
        request = AddMotion.Request(motion=motion, overwrite=True)
        future = client.call_async(request)
        rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
        if future.result() is None or not future.result().success:
            print(f'load_motions: {key} rejected', flush=True)
            failures += 1
        else:
            print(f'load_motions: {key} loaded', flush=True)
    os._exit(1 if failures else 0)


if __name__ == '__main__':
    main()
