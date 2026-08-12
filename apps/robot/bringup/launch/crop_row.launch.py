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

from better_launch import BetterLaunch, launch_this

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}
JAZZY_ENV = os.path.abspath('.pixi/envs/jazzy')


def jazzy_environment():
    return {
        'HOME': os.environ['HOME'],
        'PATH': os.environ['PATH'],
        'ZENOH_CONFIG_OVERRIDE': os.environ.get('ZENOH_CONFIG_OVERRIDE', ''),
    }


@launch_this
def crop_row():
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='canopy_detector',
        name='canopy_detector',
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='canopy_navigator',
        name='canopy_navigator',
        params={
            'drive_enabled': True,
            'odom_topic': '/diff_drive_controller/odom',
            'forward_speed_mps': 0.6,
            'command_smoothing': 0.35,
        },
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='row_shuttle',
        name='row_shuttle',
        **RESPAWN,
    )
    bl.process(
        'pixi run --clean-env -e jazzy'
        f' {JAZZY_ENV}/lib/nav2_behaviors/behavior_server'
        ' --ros-args -r __node:=behavior_server'
        ' --params-file navigation/config/behaviors.yaml',
        name='behavior_server',
        env=jazzy_environment(),
        isolate_env=True,
        **RESPAWN,
    )
    bl.process(
        'pixi run --clean-env -e jazzy'
        f' {JAZZY_ENV}/lib/nav2_lifecycle_manager/lifecycle_manager'
        ' --ros-args -r __node:=behavior_lifecycle_manager'
        ' -p autostart:=true -p node_names:=[behavior_server]'
        ' -p bond_timeout:=0.0',
        name='behavior_lifecycle_manager',
        env=jazzy_environment(),
        isolate_env=True,
        **RESPAWN,
    )
