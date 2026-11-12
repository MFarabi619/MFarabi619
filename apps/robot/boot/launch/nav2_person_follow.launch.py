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


from better_launch import BetterLaunch, launch_this
from robot_boot.launch_policy import RESPAWN, TF_REMAPS
from robot_boot.zenoh_router import ensure_zenoh_router

PERSON_FOLLOW_NAV2_SERVERS = (
    ('nav2_controller', 'controller_server'),
    ('nav2_planner', 'planner_server'),
    ('nav2_bt_navigator', 'bt_navigator'),
)


@launch_this
def nav2_person_follow(params_file: str = '', behavior_tree_file: str = ''):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    params_file = params_file or bl.find('robot_navigation', 'nav2_person_follow.yaml')
    behavior_tree_file = behavior_tree_file or bl.find('robot_navigation', 'follow_point.xml')
    for package, server in PERSON_FOLLOW_NAV2_SERVERS:
        bl.node(
            package=package,
            executable=server,
            name=server,
            params=({'default_nav_to_pose_bt_xml': behavior_tree_file}
                    if server == 'bt_navigator' else {}),
            param_files=[params_file],
            remaps=TF_REMAPS,
            **RESPAWN,
        )
    bl.node(
        package='robot_perception',
        executable='person_goal_bridge',
        name='person_goal_bridge',
        remaps=TF_REMAPS,
        **RESPAWN,
    )
