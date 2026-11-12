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


@launch_this
def slam(robot: str = '', use_sim_time: bool = False, scan_topic: str = ''):
    bl = BetterLaunch()
    if not scan_topic:
        scan_topic = (f'/{robot}/sensors/camera_0/scan' if robot
                      else '/sensors/camera_0/scan')
    tf_remaps = ({'/tf': f'/{robot}/tf', '/tf_static': f'/{robot}/tf_static'}
                 if robot else {})
    bl.node(
        package='slam_toolbox',
        executable='sync_slam_toolbox_node',
        name='slam_toolbox',
        params={'scan_topic': scan_topic, 'use_sim_time': use_sim_time},
        param_files=[bl.find('robot_navigation', 'slam.yaml')],
        remaps=tf_remaps,
    )
