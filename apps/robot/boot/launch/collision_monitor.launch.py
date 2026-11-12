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
from robot_boot.launch_policy import RESPAWN, TF_REMAPS, parameter_overrides_file
from robot_boot.zenoh_router import ensure_router


@launch_this
def collision_monitor(params_file: str = '', cloud_topic: str = 'sensors/camera_0/depth/points'):
    bl = BetterLaunch()
    ensure_router(bl)
    params_file = params_file or bl.find('robot_control', 'collision_monitor.yaml')
    bl.node(
        package='nav2_collision_monitor',
        executable='collision_monitor',
        name='collision_monitor',
        param_files=[
            params_file,
            parameter_overrides_file(
                {'collision_monitor': {'point_cloud': {'topic': cloud_topic}}}),
        ],
        remaps=TF_REMAPS,
        **RESPAWN,
    )
