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

CMD_VEL_REMAPS = {'/joy_teleop/cmd_vel': 'joy_teleop/cmd_vel'}


@launch_this
def hand_gesture_teleop(
    image_topic: str = 'sensors/camera_0/color/image_raw/compressed',
    start_enabled: bool = False,
    num_hands: int = 2,
    min_hand_detection_confidence: float = 0.4,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='robot_perception',
        executable='hand_gesture_detector',
        name='hand_gesture_detector',
        params={
            'image_topic': image_topic,
            'start_enabled': start_enabled,
            'num_hands': num_hands,
            'min_hand_detection_confidence': min_hand_detection_confidence,
        },
        remaps=CMD_VEL_REMAPS,
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='hand_gesture_teleop',
        name='hand_gesture_teleop',
        params={'start_enabled': start_enabled},
        remaps=CMD_VEL_REMAPS,
        **RESPAWN,
    )
