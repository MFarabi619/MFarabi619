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
import subprocess

from geometry_msgs.msg import PoseStamped
from moveit.core.robot_state import RobotState
from moveit.planning import MoveItPy
from ament_index_python.packages import get_package_share_directory
from moveit_configs_utils import MoveItConfigsBuilder
import rclpy
from robot_boot.zenoh_router import connect_to_zenoh_router
from robot_machines.machine import load_machine

GOAL_FRAME = 'base_link'
END_EFFECTOR_LINK = 'end_effector_link'


def arm_configuration(arm):
    configuration = (
        MoveItConfigsBuilder(arm.moveit_robot_name, package_name=arm.moveit_package)
        .planning_pipelines(pipelines=['ompl'])
        .moveit_cpp(os.path.join(
            get_package_share_directory('robot_manipulation'), 'config', 'moveit_py.yaml'))
        .to_moveit_configs().to_dict())
    configuration['use_sim_time'] = True
    configuration.setdefault('trajectory_execution', {})[
        'execution_duration_monitoring'] = False
    return configuration


def ensure_trajectory_mode():
    subprocess.run([
        'ros2', 'control', 'switch_controllers',
        '--activate', 'joint_trajectory_controller',
        '--deactivate', 'motion_control_handle', 'cartesian_motion_controller',
    ], capture_output=True)


def goal_pose(x, y, z):
    pose = PoseStamped()
    pose.header.frame_id = GOAL_FRAME
    pose.pose.position.x = x
    pose.pose.position.y = y
    pose.pose.position.z = z
    return pose


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='kinova-link-6')
    parser.add_argument('--target', default='')
    parser.add_argument('--x', type=float, default=None)
    parser.add_argument('--y', type=float, default=None)
    parser.add_argument('--z', type=float, default=None)
    arguments = parser.parse_args()
    machine = load_machine(arguments.robot)

    connect_to_zenoh_router(arguments.robot)
    ensure_trajectory_mode()
    rclpy.init()
    moveit = MoveItPy(node_name='reach', config_dict=arm_configuration(machine.arm))
    planning_component = moveit.get_planning_component('arm')
    planning_component.set_start_state_to_current_state()
    if arguments.target:
        planning_component.set_goal_state(configuration_name=arguments.target)
    elif arguments.x is not None:
        planning_component.set_goal_state(
            pose_stamped_msg=goal_pose(arguments.x, arguments.y, arguments.z),
            pose_link=END_EFFECTOR_LINK)
    else:
        goal_state = RobotState(moveit.get_robot_model())
        goal_state.set_joint_group_positions(
            'arm',
            machine.manipulation['demonstration_joint_positions_radians'])
        planning_component.set_goal_state(robot_state=goal_state)
    plan_result = planning_component.plan()
    if not plan_result:
        print('reach: planning failed', flush=True)
        os._exit(1)
    status = moveit.execute(plan_result.trajectory, controllers=[])
    if 'SUCCEEDED' not in status.status:
        print(f'reach: execution failed ({status.status})', flush=True)
        os._exit(1)
    print('reach: goal reached', flush=True)
    os._exit(0)


if __name__ == '__main__':
    main()
