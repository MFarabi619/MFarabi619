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


import subprocess

from better_launch import BetterLaunch, launch_this
from pygnssutils import OUTPUT_SERIAL
from robot_boot.launch_policy import RESPAWN
from robot_boot.zenoh_router import ensure_router

NTRIP_RESPAWN = {'max_respawns': -1, 'respawn_delay': 10.0}
NTRIP_CASTER_HOST = 'rtk2go.com'
GPS_TOPICS = ('fix', 'vel', 'time_reference', 'heading')


def assert_receiver_flash(bl, port, flash):
    completed = subprocess.run(
        [bl.find('robot_drivers', 'ublox_flash'), '--port', port, *flash.split(',')],
        capture_output=True, text=True)
    for line in completed.stdout.splitlines():
        print(line)
    if completed.returncode != 0:
        print(f'GNSS flash configuration failed: {completed.stderr.strip()}')


@launch_this
def gps(
    port: str = '/dev/ttyACM0',
    baud: int = 115200,
    frame_id: str = 'gps_link',
    topic_prefix: str = 'sensors/gps_0',
    flash: str = '',
    ntrip_mountpoint: str = '',
    ntrip_username: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    if flash:
        assert_receiver_flash(bl, port, flash)
    bl.node(
        package='nmea_navsat_driver',
        executable='nmea_serial_driver',
        name='nmea_navsat_driver',
        params={'port': port, 'baud': baud, 'frame_id': frame_id},
        remaps={topic: f'{topic_prefix}/{topic}' for topic in GPS_TOPICS},
        **RESPAWN,
    )
    if ntrip_mountpoint:
        bl.process(
            'gnssntripclient'
            f' --server {NTRIP_CASTER_HOST} --ntripversion 1.0'
            f' --mountpoint {ntrip_mountpoint}'
            f' --ntripuser {ntrip_username} --ntrippassword none'
            f' --clioutput {OUTPUT_SERIAL}'
            f' --output {port}@{baud}',
            name='ntrip_client',
            **NTRIP_RESPAWN,
        )
