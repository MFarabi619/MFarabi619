#!/usr/bin/env bash
set -euo pipefail

PORT=/dev/cu.usbmodem101
BUS=i2c@60027000

mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x00 0x03"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x5a"
sleep 0.5

echo "grand sweep"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x3c"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x00"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x3c"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x78"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0xb4"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x78"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x3c"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x00"

sleep 0.5
echo "triple salute"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0xb4"
sleep 0.3
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x00"
sleep 0.3
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0xb4"
sleep 0.3
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x00"
sleep 0.3
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0xb4"
sleep 0.3
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x00"
sleep 0.3

echo "vibrato"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x69"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x4b"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x69"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x4b"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x69"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x4b"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x69"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x4b"

echo "bow"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0xb4"
sleep 0.4
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x87"
mcumgrctl --serial $PORT shell "i2c write_byte $BUS 0x25 0x50 0x5a"
