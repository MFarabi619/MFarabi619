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
import tempfile

import yaml

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import (
    read_robot_description,
    robot_state_publisher,
    spawn_controller,
)


def render_scene():
    apple_assets = os.path.abspath(
        'simulation/models/ycb/013_apple/google_16k')
    with open(os.path.abspath(
            'manipulation/config/mujoco_scene.xml')) as template:
        scene = template.read().replace('${APPLE_ASSETS}', apple_assets)
    scene_file = tempfile.NamedTemporaryFile(
        mode='w', suffix='.xml', delete=False)
    scene_file.write(scene)
    scene_file.close()
    return scene_file.name


@launch_this(use_sim_time=True)
def arm_mujoco_simulation(robot: str = 'kinova-link-6', mode: str = 'moveit'):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        arm = yaml.safe_load(machine_file)['arm']
    install_arm = os.path.abspath('install-arm')
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
    description = read_robot_description(
        arm['description_package'],
        f"{arm['moveit_robot_name']}.urdf.xacro",
        xacro_args=[
            f"gripper:={arm['gripper']}",
            'sim_mujoco:=true',
            'use_fake_hardware:=true',
        ],
    )
    robot_state_publisher(
        description, node_name='robot_state_publisher', anonymous=False)
    bl.process(
        [os.path.join(install_arm, 'lib', 'mujoco_ros2_control',
                      'robot_description_to_mjcf.sh'),
         '--publish_topic', '/mujoco_robot_description',
         '--convert_stl_to_obj',
         '--mujoco_inputs',
         os.path.abspath('manipulation/config/mujoco_inputs.xml'),
         '--scene',
         render_scene()],
        name='mjcf_converter',
    )
    bl.node(
        'controller_manager', 'ros2_control_node',
        name='controller_manager',
        anonymous=False,
        param_files=[
            os.path.join(
                install_arm, 'share', arm['control_package'], 'config',
                'kortex3_sim_controllers.yaml'),
            os.path.abspath('manipulation/config/mujoco_plugins.yaml'),
        ],
        use_sim_time=True,
    )
    spawn_controller('joint_state_broadcaster')
    spawn_controller('joint_trajectory_controller')
    spawn_controller('robotiq_gripper_controller')

    if mode == 'moveit':
        bl.process(
            'python manipulation/src/mujoco_planning_scene.py',
            name='mujoco_planning_scene',
        )
        bl.include(
            arm['moveit_package'], 'move_group.launch.py',
            pass_launch_func_args=False,
            use_sim_time='true',
            capabilities='move_group/ExecuteTaskSolutionCapability',
        )
        bl.include(
            'play_motion2', 'play_motion2.launch.py',
            pass_launch_func_args=False,
            motions_file=os.path.abspath(f'machines/{robot}/motions.yaml'),
            motion_planner_config=os.path.abspath(
                'manipulation/config/motion_planner.yaml'),
            use_sim_time='true',
        )
        bl.process(
            'rviz2 -d ' + os.path.abspath('manipulation/config/moveit.rviz')
            + ' --ros-args -p use_sim_time:=true',
            name='rviz',
        )
    else:
        bl.process(
            'rviz2 -d ' + os.path.join(
                install_arm, 'share', arm['control_package'], 'config',
                'link6_config.rviz')
            + ' --ros-args -p use_sim_time:=true',
            name='rviz',
        )
