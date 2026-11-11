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

import yaml

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import (
    read_robot_description,
    robot_state_publisher,
)

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


@launch_this
def arm_hardware(
        robot: str = 'kinova-link-6',
        robot_password: str = 'admin',
        rviz: bool = True):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        robot_config = yaml.safe_load(machine_file)
    arm = robot_config['arm']
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)

    bl = BetterLaunch()
    bl.process(
        os.path.join(
            os.environ['CONDA_PREFIX'], 'lib', 'rmw_zenoh_cpp', 'rmw_zenohd'),
        name='zenoh_router',
        **RESPAWN,
    )
    bl.process(
        [os.path.abspath('.pixi/envs/kortex/bin/python'),
         'manipulation/src/kinova_link6_bridge.py',
         '--robot-password', robot_password],
        name='kinova_link6_bridge',
        env={'PYTHONPATH': ''},
        **RESPAWN,
    )
    description = read_robot_description(
        arm['description_package'],
        f"{arm['moveit_robot_name']}.urdf.xacro",
        xacro_args=[f"gripper:={arm['gripper']}"],
    )
    share_prefix = os.path.abspath('install-arm/share') + '/'
    description = description.replace('file://' + share_prefix, 'package://')
    description = description.replace(share_prefix, 'package://')
    robot_state_publisher(description)
    bl.process(
        'python manipulation/src/kinova_link6_bridge_node.py --ros-args'
        ' -r arm_teleop/cmd_vel:=/joy_teleop/cmd_vel',
        name='kinova_link6_bridge_node',
    )
    bl.include(
        arm['moveit_package'], 'move_group.launch.py',
        pass_launch_func_args=False,
    )
    bl.include(
        'play_motion2', 'play_motion2.launch.py',
        pass_launch_func_args=False,
        motions_file=os.path.abspath(f'machines/{robot}/motions.yaml'),
        motion_planner_config=os.path.abspath(
            'manipulation/config/motion_planner.yaml'),
        use_sim_time='false',
    )

    if robot_config.get('foxglove', {}).get('enabled', True):
        bl.node(
            package='foxglove_bridge',
            executable='foxglove_bridge',
            name='foxglove_bridge',
            params={
                'send_buffer_limit': 20000000,
                'max_qos_depth': 5,
                'asset_uri_allowlist': [
                    '^package://(?:[-\\w%]+/)*[-\\w%.]+\\.'
                    '(?:dae|fbx|glb|gltf|jpeg|jpg|mtl|obj|png|stl|STL'
                    '|tif|tiff|urdf|webp|xacro)$',
                ],
                'best_effort_qos_topic_whitelist': [
                    '/sensors/camera_[0-9]+/.*',
                ],
                'topic_whitelist': [
                    '/perception/.*',
                    '/sensors/camera_[0-9]+/color/image_raw/compressed$',
                    '/sensors/camera_[0-9]+/depth/image_view/compressed$',
                    '/sensors/camera_[0-9]+/(color|depth)/camera_info$',
                    '/sensors/camera_[0-9]+/depth/points$',
                    '/sensors/camera_[0-9]+/imu/data$',
                    '/joint_states$',
                    '/tf(_static)?$',
                    '/robot_description$',
                    '/camera_[0-9]+_description$',
                    '/diagnostics.*',
                ],
            },
            **RESPAWN,
        )

    if rviz:
        bl.process(
            'rviz2 -d ' + os.path.abspath('manipulation/config/moveit.rviz'),
            name='rviz',
        )
