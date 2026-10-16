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


import yaml

from better_launch import BetterLaunch, launch_this
from moveit_configs_utils import MoveItConfigsBuilder


@launch_this(use_sim_time=True)
def kinova_link6_pick(robot: str = 'kinova-link-6', object: str = 'apple'):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        arm = yaml.safe_load(machine_file)['arm']
    moveit_configuration = (
        MoveItConfigsBuilder(
            arm['moveit_robot_name'], package_name=arm['moveit_package'])
        .planning_pipelines(pipelines=['ompl'])
        .to_moveit_configs().to_dict())

    bl = BetterLaunch()
    bl.node(
        'robot_manipulation', 'kinova_link6_pick',
        name='pick_task',
        params={**moveit_configuration, 'object': object},
    )
