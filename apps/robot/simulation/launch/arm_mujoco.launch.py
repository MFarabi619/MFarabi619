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

from better_launch import BetterLaunch, launch_this
from better_launch.convenience import (
    read_robot_description,
    robot_state_publisher,
    spawn_controller,
)
from robot_boot.launch_policy import include
from robot_boot.zenoh_router import ensure_zenoh_router
from robot_machines.machine import load_machine


def write_rendered_scene_file(bl):
    apple_assets_directory = os.path.dirname(
        bl.find('robot_simulation', 'textured.obj', subdir='models/ycb/013_apple/google_16k'))
    with open(bl.find('robot_manipulation', 'mujoco_scene.xml')) as template:
        scene = template.read().replace('${APPLE_ASSETS}', apple_assets_directory)
    scene_tempfile = tempfile.NamedTemporaryFile(mode='w', suffix='.xml', delete=False)
    scene_tempfile.write(scene)
    scene_tempfile.close()
    return scene_tempfile.name


@launch_this(use_sim_time=True)
def arm_mujoco(
        robot: str = 'kinova-link-6', mode: str = 'moveit',
        headless: bool = False):
    machine = load_machine(robot)
    os.environ.pop('ZENOH_CONFIG_OVERRIDE', None)
    os.environ.pop('ZENOH_SESSION_CONFIG_URI', None)

    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    description = read_robot_description(
        machine.arm.description_package,
        f'{machine.arm.moveit_robot_name}.urdf.xacro',
        xacro_args=[
            f'gripper:={machine.arm.gripper}',
            'sim_mujoco:=true',
            'use_fake_hardware:=true',
        ],
    )
    robot_state_publisher(
        description, node_name='robot_state_publisher', anonymous=False)
    bl.process(
        ['python',
         bl.find('mujoco_ros2_control', 'make_mjcf_from_robot_description.py'),
         '--publish_topic', '/mujoco_robot_description',
         '--convert_stl_to_obj',
         '--mujoco_inputs', bl.find('robot_manipulation', 'mujoco_inputs.xml'),
         '--scene', write_rendered_scene_file(bl)],
        name='mjcf_converter',
    )
    controller_parameters_file = bl.find(
        machine.arm.control_package, 'kortex3_sim_controllers.yaml')
    bl.node(
        'controller_manager', 'ros2_control_node',
        name='controller_manager',
        anonymous=False,
        remap_qualifier='controller_manager',
        param_files=[
            controller_parameters_file,
            bl.find('robot_manipulation', 'mujoco_plugins.yaml'),
        ],
        use_sim_time=True,
    )
    spawn_controller('joint_state_broadcaster')
    spawn_controller('joint_trajectory_controller', params=[controller_parameters_file])
    spawn_controller('robotiq_gripper_controller', params=[controller_parameters_file])

    if mode == 'moveit':
        bl.process(
            [bl.find('robot_manipulation', 'mujoco_planning_scene')],
            name='mujoco_planning_scene',
        )
        include(
            'robot_manipulation', 'kinova_link6_moveit.launch.py',
            moveit_package=machine.arm.moveit_package,
            motions_file=bl.find('robot_machines', 'motions.yaml', subdir=robot),
            use_sim_time=True,
            capabilities='move_group/ExecuteTaskSolutionCapability',
            rviz_enabled=not headless,
        )
    elif not headless:
        bl.process(
            ['rviz2', '-d', bl.find(machine.arm.control_package, 'link6_config.rviz'),
             '--ros-args', '-p', 'use_sim_time:=true'],
            name='rviz',
        )
