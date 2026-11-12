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
from robot_boot.launch_policy import RESPAWN
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def twist_mux(params_file: str = '', cmd_vel_out: str = 'platform/cmd_vel'):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    params_file = params_file or bl.find('robot_control', 'twist_mux.yaml')
    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        remaps={'cmd_vel_out': cmd_vel_out},
        param_files=[params_file],
        **RESPAWN,
    )
