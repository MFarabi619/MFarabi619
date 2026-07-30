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
from better_launch.gazebo import spawn_topic_bridge


@launch_this(use_sim_time=True)
def simulation(world: str = 'maize', headless: bool = False):
    bl = BetterLaunch()
    # bl.process(
    #     'ros2 run rmw_zenoh_cpp rmw_zenohd',
    #     name='zenoh_router',
    #     max_respawns=-1,
    #     respawn_delay=2.0,
    # )
    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        param_files='apps/robot/control/config/twist_mux.yaml',
        remaps={'cmd_vel_out': 'platform/cmd_vel'},
    )
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={
            'port': 8765,
            'send_buffer_limit': 1000000,
            'max_qos_depth': 5,
            'best_effort_qos_topic_whitelist': ['/sensors/camera_.*'],
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )
    spawn_topic_bridge(
        '/scan@sensor_msgs/msg/LaserScan[gz.msgs.LaserScan',
        node_name='scan_bridge',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='row_detector',
        name='crop_row_detector',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='gesture_teleop',
        name='gesture_teleop',
        params={'image_topic': '/image'},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='gesture_to_cmd_vel',
        name='gesture_to_cmd_vel',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.include('robot_gz', 'gz_sim.launch.py', world=world, headless=headless)
    bl.include('robot_gz', 'robot_spawn.launch.py', pass_launch_func_args=False)
