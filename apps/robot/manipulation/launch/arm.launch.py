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
from better_launch.convenience import robot_state_publisher


@launch_this
def arm_hardware(robot: str = 'kinova-link-6', robot_password: str = 'admin'):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        arm = yaml.safe_load(machine_file)['arm']
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)

    bl = BetterLaunch()
    bl.process(
        os.path.join(
            os.environ['CONDA_PREFIX'], 'lib', 'rmw_zenoh_cpp', 'rmw_zenohd'),
        name='zenoh_router',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.process(
        [os.path.abspath('.pixi/envs/kortex/bin/python'),
         'manipulation/src/kinova_link6_bridge.py',
         '--robot-password', robot_password],
        name='kinova_link6_bridge',
        env={'PYTHONPATH': ''},
    )
    robot_state_publisher(
        bl.find(arm['description_package'],
                f"{arm['moveit_robot_name']}.urdf.xacro"),
        xacro_args=[f"gripper:={arm['gripper']}"],
    )
    bl.process(
        'python manipulation/src/kinova_link6_bridge_node.py',
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
    bl.process(
        'rviz2 -d ' + os.path.abspath('manipulation/config/moveit.rviz'),
        name='rviz',
    )
