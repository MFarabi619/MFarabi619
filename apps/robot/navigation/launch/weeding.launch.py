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
def weeding(start_enabled: bool = False):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='robot_navigation',
        executable='weeding_creep',
        name='weeding_creep',
        params={'start_enabled': start_enabled},
        remaps=TF_REMAPS,
        **RESPAWN,
    )
    bl.node(
        package='robot_navigation',
        executable='lay_down_weeding_elbow_teleop',
        name='lay_down_weeding_elbow_teleop',
        params={'start_enabled': start_enabled},
        **RESPAWN,
    )
