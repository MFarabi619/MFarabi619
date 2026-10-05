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


import argparse
import sys
import time

from pyubx2 import SET, UBXMessage, UBXReader
from serial import Serial

UBLOX_PORT = ('/dev/serial/by-id/'
              'usb-u-blox_AG_-_www.u-blox.com_u-blox_GNSS_receiver-if00')
ACKNOWLEDGEMENT_WAIT_SECONDS = 3.0


def send_and_confirm(port, message):
    port.write(message.serialize())
    reader = UBXReader(port)
    deadline = time.monotonic() + ACKNOWLEDGEMENT_WAIT_SECONDS
    while time.monotonic() < deadline:
        _, parsed = reader.read()
        if parsed is None:
            continue
        if parsed.identity == 'ACK-ACK':
            return
        if parsed.identity == 'ACK-NAK':
            sys.exit(f'receiver rejected {message.identity}')
    sys.exit(f'no acknowledgement for {message.identity}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default=UBLOX_PORT)
    parser.add_argument('--rate_hz', type=int, default=10)
    arguments = parser.parse_args()

    measurement_interval_ms = round(1000 / arguments.rate_hz)
    with Serial(arguments.port, 115200, timeout=1.0) as port:
        send_and_confirm(port, UBXMessage(
            'CFG', 'CFG-RATE', SET,
            measRate=measurement_interval_ms, navRate=1, timeRef=1))
        send_and_confirm(port, UBXMessage(
            'CFG', 'CFG-CFG', SET,
            clearMask=b'\x00\x00\x00\x00',
            saveMask=b'\x1f\x1f\x00\x00',
            loadMask=b'\x00\x00\x00\x00',
            devBBR=1, devFlash=1))
    print(f'navigation rate set to {arguments.rate_hz} Hz and saved to flash')


if __name__ == '__main__':
    main()
