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
from robot_boot.launch_policy import (
    LIFECYCLE_ACTIVATION, NAV2_COSTMAPS, NAV2_SERVERS, RESPAWN, TF_REMAPS,
    write_parameter_overrides_file)
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def nav2_navigate_to_pose(
    params_file: str = '',
    behavior_tree_file: str = '',
    scan_topic: str = 'sensors/camera_0/scan',
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    robot_namespace = bl.group_tip.assemble_namespace().rstrip('/')
    params_file = params_file or bl.find('robot_navigation', 'nav2_navigate_to_pose.yaml')
    behavior_tree_file = behavior_tree_file or bl.find('robot_navigation', 'navigate_to_pose.xml')
    scan_overrides_file = write_parameter_overrides_file({
        costmap: {'obstacle_layer': {'scan': {'topic': f'{robot_namespace}/{scan_topic}'}}}
        for costmap in NAV2_COSTMAPS
    })
    for package, server in NAV2_SERVERS:
        bl.node(
            package=package,
            executable=server,
            name=server,
            params=({'default_nav_to_pose_bt_xml': behavior_tree_file}
                    if server == 'bt_navigator' else {}),
            param_files=[params_file, scan_overrides_file],
            remaps=TF_REMAPS,
            **RESPAWN,
            **LIFECYCLE_ACTIVATION,
        )
