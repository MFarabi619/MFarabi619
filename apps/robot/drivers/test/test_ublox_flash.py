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


import struct

import pytest
from pyubx2 import GET, UBXMessage
from pyubx2.ubxhelpers import cfgname2key, val2bytes


class ScriptedUbxPort:
    def __init__(self, replies=b''):
        self.written = []
        self.read_buffer = replies

    def write(self, data):
        self.written.append(bytes(data))

    def read(self, size=1):
        chunk = self.read_buffer[:size]
        self.read_buffer = self.read_buffer[size:]
        return chunk


def valget_reply(**values):
    payload = b'\x01\x00\x00\x00'
    for name, value in values.items():
        key, attribute = cfgname2key(name)
        payload += struct.pack('<I', key) + val2bytes(value, attribute)
    return UBXMessage(b'\x06', b'\x8b', GET, payload=payload).serialize()


def acknowledgement(accepted=True):
    identity = 'ACK-ACK' if accepted else 'ACK-NAK'
    return UBXMessage(
        'ACK', identity, GET, clsID=0x06, msgID=0x8a).serialize()


def test_in_sync_receiver_is_left_untouched(ublox_flash_module):
    port = ScriptedUbxPort(
        valget_reply(CFG_RATE_MEAS=200, CFG_RATE_NAV=1))
    corrections = ublox_flash_module.assert_flash(
        port, {'CFG_RATE_MEAS': 200, 'CFG_RATE_NAV': 1})
    assert corrections == []
    assert len(port.written) == 1


def test_drift_is_corrected_and_verified(ublox_flash_module):
    port = ScriptedUbxPort(
        valget_reply(CFG_RATE_MEAS=1000, CFG_RATE_NAV=1)
        + acknowledgement()
        + valget_reply(CFG_RATE_MEAS=200))
    corrections = ublox_flash_module.assert_flash(
        port, {'CFG_RATE_MEAS': 200, 'CFG_RATE_NAV': 1})
    assert corrections == ['CFG_RATE_MEAS=200']
    assert len(port.written) == 3


def test_rejected_configuration_raises(ublox_flash_module):
    port = ScriptedUbxPort(
        valget_reply(CFG_RATE_MEAS=1000)
        + acknowledgement(accepted=False))
    with pytest.raises(RuntimeError, match='rejected'):
        ublox_flash_module.assert_flash(port, {'CFG_RATE_MEAS': 200})


def test_readback_mismatch_raises(ublox_flash_module):
    port = ScriptedUbxPort(
        valget_reply(CFG_RATE_MEAS=1000)
        + acknowledgement()
        + valget_reply(CFG_RATE_MEAS=1000))
    with pytest.raises(RuntimeError, match='readback mismatch'):
        ublox_flash_module.assert_flash(port, {'CFG_RATE_MEAS': 200})
