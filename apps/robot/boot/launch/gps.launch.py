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
from pygnssutils import OUTPUT_SERIAL
from zenoh_router import ensure_router

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}
NTRIP_RESPAWN = {'max_respawns': -1, 'respawn_delay': 10.0}
NTRIP_CASTER_HOST = 'rtk2go.com'
GPS_TOPICS = ['fix', 'vel', 'time_reference', 'heading']


@launch_this
def gps(
    port: str = '/dev/cu.usbmodem2101',
    baud: int = 115200,
    mountpoint: str = 'OsgoodeFarms',
    ntrip_username: str = 'farabi@tandemrobotics.ca',
):
    bl = BetterLaunch()
    ensure_router(bl)
    if mountpoint:
        bl.process(
            ['gnssntripclient', '--server', NTRIP_CASTER_HOST,
             '--ntripversion', '1.0', '--mountpoint', mountpoint,
             '--ntripuser', ntrip_username, '--ntrippassword', 'none',
             '--clioutput', str(OUTPUT_SERIAL), '--output', f'{port}@{baud}'],
            name='ntrip_client',
            **NTRIP_RESPAWN,
        )
    bl.node(
        package='nmea_navsat_driver',
        executable='nmea_serial_driver',
        name='nmea_navsat_driver',
        params={'port': port, 'baud': baud, 'frame_id': 'gps_link'},
        remaps={topic: f'sensors/gps_0/{topic}' for topic in GPS_TOPICS},
        **RESPAWN,
    )
