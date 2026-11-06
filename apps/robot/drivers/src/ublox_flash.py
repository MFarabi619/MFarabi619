#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# u-blox GNSS receiver flash configuration assert (UBX VALGET/VALSET)


import argparse
import time

from pyubx2 import (
    POLL_LAYER_RAM,
    SET_LAYER_BBR,
    SET_LAYER_FLASH,
    SET_LAYER_RAM,
    UBX_PROTOCOL,
    UBXMessage,
    UBXReader,
)
import serial

REPLY_TIMEOUT_SECONDS = 3.0
PERSISTENT_LAYERS = SET_LAYER_RAM | SET_LAYER_BBR | SET_LAYER_FLASH


def read_message(port, identities):
    reader = UBXReader(port, protfilter=UBX_PROTOCOL)
    deadline = time.monotonic() + REPLY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        _, parsed = reader.read()
        if parsed is not None and parsed.identity in identities:
            return parsed
    raise TimeoutError(f'no {"/".join(identities)} reply')


def poll_values(port, keys):
    port.write(UBXMessage.config_poll(POLL_LAYER_RAM, 0, keys).serialize())
    reply = read_message(port, ('CFG-VALGET',))
    return {key: getattr(reply, key) for key in keys}


def assert_flash(port, declared):
    current = poll_values(port, list(declared))
    drifted = {
        key: value for key, value in declared.items()
        if current[key] != value
    }
    if not drifted:
        return []
    port.write(UBXMessage.config_set(
        PERSISTENT_LAYERS, 0, list(drifted.items())).serialize())
    acknowledgement = read_message(port, ('ACK-ACK', 'ACK-NAK'))
    if acknowledgement.identity == 'ACK-NAK':
        raise RuntimeError(
            f'receiver rejected configuration: {", ".join(drifted)}')
    verified = poll_values(port, list(drifted))
    rejected = [
        key for key, value in drifted.items() if verified[key] != value]
    if rejected:
        raise RuntimeError(f'readback mismatch: {", ".join(rejected)}')
    return [f'{key}={value}' for key, value in drifted.items()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', required=True)
    parser.add_argument('declarations', nargs='+')
    arguments = parser.parse_args()
    declared = {}
    for declaration in arguments.declarations:
        key, _, value = declaration.partition('=')
        declared[key] = int(value)
    port = serial.Serial(arguments.port, 115200, timeout=0.5)
    try:
        for correction in assert_flash(port, declared):
            print(f'flash configuration corrected: {correction}')
    finally:
        port.close()


if __name__ == '__main__':
    main()
