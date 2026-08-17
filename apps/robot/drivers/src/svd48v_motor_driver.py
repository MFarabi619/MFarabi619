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

# UUMotor SVD48V dual hub motor servo driver (Modbus RTU, CRC sent high byte first)
# Manual: assets/SVD48V30A-user-manual-V2.0.pdf


import math
import struct

import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
import serial

from robot_platform_msgs.msg import Drive, Feedback


FEEDBACK_RATE_HZ = 50.0
COMMAND_TIMEOUT_SECONDS = 0.5
SERIAL_TIMEOUT_SECONDS = 0.1
RPM_PER_RADIAN_PER_SECOND = 60.0 / math.tau

READ_HOLDING_REGISTERS = 0x03
WRITE_SINGLE_REGISTER = 0x06
WRITE_MULTIPLE_REGISTERS = 0x10

CONTROL_MODE_REGISTER = 0x5100
CONTROL_MODE_SPEED = 0
ACCELERATION_REGISTER = 0x5108
DECELERATION_REGISTER = 0x510C
SPEED_SMOOTHING_REGISTER = 0x5110
CONTROL_COMMAND_REGISTER = 0x5300
CONTROL_COMMAND_STOP = 0
CONTROL_COMMAND_START = 1
CONTROL_COMMAND_CLEAR_ALARM = 2
GIVEN_SPEED_REGISTER = 0x5304
MOTOR_TEMPERATURE_REGISTER = 0x5404
BRIDGE_TEMPERATURE_REGISTER = 0x540C
SPEED_REGISTER = 0x5410
CURRENT_REGISTER = 0x5414
POSITION_REGISTER = 0x5418
ERROR_CODE_REGISTER = 0x5420
FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ = 25
TENTHS_PER_UNIT = 10.0

ERROR_BIT_NAMES = {
    0: 'current sampling abnormal',
    1: 'overcurrent protection circuit abnormal',
    2: 'motor cable short',
    3: 'bus voltage out of range',
    4: 'drive temperature abnormal',
    5: 'drive 12V abnormal',
    6: 'drive 5V abnormal',
    7: 'motor circuit open',
    8: 'drive overtemperature',
    9: 'motor overtemperature',
    10: 'motor overcurrent',
    11: 'motor overload',
    12: 'overvoltage',
    13: 'undervoltage',
    14: 'encoder input abnormal',
    15: 'wrong hardware version',
}


def crc16_modbus(frame):
    crc = 0xFFFF
    for byte in frame:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return bytes([crc >> 8, crc & 0xFF])


def decode_error_bits(error_code):
    return ', '.join(
        name for bit, name in ERROR_BIT_NAMES.items() if error_code & (1 << bit))


class Svd48vBus:
    def __init__(self, port, baud, address):
        self.port = serial.Serial(port, baud, timeout=SERIAL_TIMEOUT_SECONDS)
        self.address = address

    def transact(self, frame, reply_length):
        request = frame + crc16_modbus(frame)
        self.port.reset_input_buffer()
        self.port.write(request)
        reply = self.port.read(reply_length)
        if len(reply) < reply_length:
            raise TimeoutError(f'short reply: {reply.hex()}')
        if crc16_modbus(reply[:-2]) != reply[-2:]:
            raise ValueError(f'bad crc: {reply.hex()}')
        return reply

    def read_registers(self, register, count):
        frame = struct.pack(
            '>BBHH', self.address, READ_HOLDING_REGISTERS, register, count)
        reply = self.transact(frame, 5 + 2 * count)
        return reply[3:-2]

    def write_register(self, register, value):
        frame = struct.pack(
            '>BBHH', self.address, WRITE_SINGLE_REGISTER, register,
            value & 0xFFFF)
        self.transact(frame, 8)

    def write_registers(self, register, values):
        packed_values = b''.join(
            struct.pack('>H', value & 0xFFFF) for value in values)
        frame = struct.pack(
            '>BBHHB', self.address, WRITE_MULTIPLE_REGISTERS, register,
            len(values), len(packed_values)) + packed_values
        self.transact(frame, 8)


class Svd48vMotorDriver(Node):
    def __init__(self):
        super().__init__('svd48v_motor_driver')
        self.declare_parameter('serial_port', '/dev/ttyUSB0')
        self.declare_parameter('baud_rate', 115200)
        self.declare_parameter('address', 0xEE)
        self.declare_parameter('max_wheel_speed', 1.0)
        self.declare_parameter('acceleration_rpm_per_second', 1000)
        self.declare_parameter('speed_smoothing_time', 50)
        for side in ('left', 'right'):
            self.declare_parameter(f'{side}_reversed', False)

        self.max_wheel_speed = self.get_parameter('max_wheel_speed').value
        self.direction_signs = [
            -1.0 if self.get_parameter(f'{side}_reversed').value else 1.0
            for side in ('left', 'right')
        ]
        self.bus = Svd48vBus(
            self.get_parameter('serial_port').value,
            self.get_parameter('baud_rate').value,
            self.get_parameter('address').value,
        )
        self.last_error_codes = [0, 0]
        self.currents = [0.0, 0.0]
        self.motor_temperatures = [0.0, 0.0]
        self.bridge_temperatures = [0.0, 0.0]
        self.feedback_tick = 0
        self.configure_drive()
        self.get_logger().info('connected SVD48V')

        self.commanded_mode = Drive.MODE_NONE
        self.last_command_time = self.get_clock().now()
        self.drive_subscription = self.create_subscription(
            Drive, 'platform/motors/cmd_drive', self.on_drive,
            qos_profile_sensor_data)
        self.feedback_publisher = self.create_publisher(
            Feedback, 'platform/motors/feedback', qos_profile_sensor_data)
        self.feedback_timer = self.create_timer(
            1.0 / FEEDBACK_RATE_HZ, self.publish_feedback)

    def configure_drive(self):
        # TODO: verify whether board control input register 0x3008 must be
        # switched for serial motion commands once motors arrive
        acceleration = self.get_parameter('acceleration_rpm_per_second').value
        smoothing = self.get_parameter('speed_smoothing_time').value
        self.bus.write_registers(
            CONTROL_MODE_REGISTER, [CONTROL_MODE_SPEED, CONTROL_MODE_SPEED])
        self.bus.write_registers(
            ACCELERATION_REGISTER, [acceleration, acceleration])
        self.bus.write_registers(
            DECELERATION_REGISTER, [acceleration, acceleration])
        self.bus.write_registers(
            SPEED_SMOOTHING_REGISTER, [smoothing, smoothing])
        self.bus.write_registers(
            CONTROL_COMMAND_REGISTER,
            [CONTROL_COMMAND_START, CONTROL_COMMAND_START])

    def rpm_from_wheel_speed(self, wheel_speed, direction_sign):
        clamped_speed = max(
            -self.max_wheel_speed, min(wheel_speed, self.max_wheel_speed))
        return int(direction_sign * clamped_speed * RPM_PER_RADIAN_PER_SECOND)

    def command_speeds(self, wheel_speeds):
        self.bus.write_registers(
            GIVEN_SPEED_REGISTER,
            [
                self.rpm_from_wheel_speed(wheel_speed, direction_sign)
                for wheel_speed, direction_sign
                in zip(wheel_speeds, self.direction_signs)
            ],
        )

    def on_drive(self, message):
        self.last_command_time = self.get_clock().now()
        self.commanded_mode = message.mode
        if message.mode == Drive.MODE_VELOCITY:
            wheel_speeds = message.drivers
        elif message.mode == Drive.MODE_PWM:
            wheel_speeds = [
                value * self.max_wheel_speed for value in message.drivers]
        else:
            wheel_speeds = [0.0, 0.0]
        try:
            self.command_speeds([float(value) for value in wheel_speeds])
        except (TimeoutError, ValueError) as error:
            self.get_logger().warning(f'command failed: {error}')

    def read_motor_pair(self, register, format_character):
        data = self.bus.read_registers(register, 2)
        return struct.unpack(f'>2{format_character}', data)

    def read_motor_pair_32(self, register, format_character):
        data = self.bus.read_registers(register, 4)
        return struct.unpack(f'>2{format_character}', data)

    def read_slow_telemetry(self):
        currents = self.read_motor_pair(CURRENT_REGISTER, 'h')
        self.currents = [value / TENTHS_PER_UNIT for value in currents]
        motor_temperatures = self.read_motor_pair(MOTOR_TEMPERATURE_REGISTER, 'h')
        self.motor_temperatures = [
            value / TENTHS_PER_UNIT for value in motor_temperatures]
        bridge_temperatures = self.read_motor_pair(
            BRIDGE_TEMPERATURE_REGISTER, 'H')
        self.bridge_temperatures = [
            value / TENTHS_PER_UNIT for value in bridge_temperatures]
        error_codes = self.read_motor_pair_32(ERROR_CODE_REGISTER, 'I')
        for motor_index, error_code in enumerate(error_codes):
            if error_code != self.last_error_codes[motor_index]:
                self.last_error_codes[motor_index] = error_code
                if error_code:
                    self.get_logger().warning(
                        f'M{motor_index + 1} error {error_code:#x}: '
                        f'{decode_error_bits(error_code)}')

    def publish_feedback(self):
        now = self.get_clock().now()
        has_timed_out = (
            now - self.last_command_time
            > Duration(seconds=COMMAND_TIMEOUT_SECONDS))
        if has_timed_out:
            try:
                self.command_speeds([0.0, 0.0])
            except (TimeoutError, ValueError):
                pass

        self.feedback_tick += 1
        try:
            speeds_rpm = self.read_motor_pair(SPEED_REGISTER, 'h')
            position_counts = self.read_motor_pair_32(POSITION_REGISTER, 'i')
            if self.feedback_tick % FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ == 0:
                self.read_slow_telemetry()
        except (TimeoutError, ValueError) as error:
            self.get_logger().warning(f'status read failed: {error}')
            return

        message = Feedback()
        message.header.stamp = now.to_msg()
        message.commanded_mode = self.commanded_mode
        message.actual_mode = (
            Drive.MODE_NONE if has_timed_out else self.commanded_mode)
        for motor_index, driver_feedback in enumerate(message.drivers):
            direction_sign = self.direction_signs[motor_index]
            driver_feedback.measured_velocity = (
                direction_sign * speeds_rpm[motor_index]
                / RPM_PER_RADIAN_PER_SECOND
            )
            # TODO: scale measured_travel from encoder counts once the hub
            # motor encoder line count is known
            driver_feedback.measured_travel = (
                direction_sign * float(position_counts[motor_index]))
            driver_feedback.current = self.currents[motor_index]
            driver_feedback.bridge_temperature = (
                self.bridge_temperatures[motor_index])
            driver_feedback.motor_temperature = (
                self.motor_temperatures[motor_index])
            driver_feedback.driver_fault = (
                self.last_error_codes[motor_index] != 0)
        self.feedback_publisher.publish(message)

    def release(self):
        self.command_speeds([0.0, 0.0])
        self.bus.write_registers(
            CONTROL_COMMAND_REGISTER,
            [CONTROL_COMMAND_STOP, CONTROL_COMMAND_STOP])


# TODO: test against a pty-simulated drive
def main():
    rclpy.init()
    node = Svd48vMotorDriver()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            node.release()
        except Exception:
            pass


if __name__ == '__main__':
    main()
