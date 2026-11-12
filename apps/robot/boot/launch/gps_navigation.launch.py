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
from robot_boot.zenoh_router import ensure_router

NAV2_SERVERS = (
    ('nav2_controller', 'controller_server'),
    ('nav2_planner', 'planner_server'),
    ('nav2_bt_navigator', 'bt_navigator'),
    ('nav2_waypoint_follower', 'waypoint_follower'),
)
COSTMAP_BY_SERVER = {
    'controller_server': 'local_costmap',
    'planner_server': 'global_costmap',
}
FROM_LL_TIMEOUT_SECONDS = 120.0


@launch_this
def gps_navigation(
    namespace: str = '',
    params_file: str = '',
    behavior_tree: str = '',
    scan_topic: str = 'sensors/camera_0/scan',
    overrides_file: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    params_file = params_file or bl.find('robot_navigation', 'gps_navigation.yaml')
    behavior_tree = behavior_tree or bl.find('robot_navigation', 'navigate_to_pose.xml')
    param_files = [params_file] + ([overrides_file] if overrides_file else [])
    bl.wait_for_service(f'/{namespace}/fromLL', timeout=FROM_LL_TIMEOUT_SECONDS)
    for package, server in NAV2_SERVERS:
        parameters = {}
        remaps = dict(TF_REMAPS)
        if server == 'bt_navigator':
            parameters['default_nav_to_pose_bt_xml'] = behavior_tree
        if server == 'waypoint_follower':
            remaps['/fromLL'] = 'fromLL'
        if server in COSTMAP_BY_SERVER:
            remaps[f'/{namespace}/{COSTMAP_BY_SERVER[server]}/{scan_topic}'] = (
                f'/{namespace}/{scan_topic}')
        bl.node(
            package=package,
            executable=server,
            name=server,
            params=parameters,
            param_files=param_files,
            remaps=remaps,
            **RESPAWN,
        )
