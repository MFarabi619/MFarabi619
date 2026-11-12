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


@launch_this
def robot_localization(params_file: str = '', gps_topic_prefix: str = 'sensors/gps_0'):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    params_file = params_file or bl.find('robot_control', 'robot_localization.yaml')
    bl.node(
        package='robot_localization',
        executable='ekf_node',
        name='ekf_global',
        param_files=[params_file],
        remaps=TF_REMAPS,
        **RESPAWN,
    )
    bl.node(
        package='robot_localization',
        executable='navsat_transform_node',
        name='navsat_transform',
        param_files=[params_file],
        remaps=TF_REMAPS | {
            'gps/fix': f'{gps_topic_prefix}/fix',
            'gps/filtered': f'{gps_topic_prefix}/filtered',
        },
        **RESPAWN,
    )
