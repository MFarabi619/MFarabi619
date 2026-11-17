#!/usr/bin/env python3

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


from adafruit_extended_bus import ExtendedI2C
import adafruit_mcp4725
from analog_throttle_wheel import AnalogThrottleWheel, cap_arc_wheel_speeds, ThrottleBand
import gpiod
from gpiod.line import Direction, Value
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from robot_platform_msgs.msg import Drive, Feedback

FEEDBACK_RATE_HZ = 50.0
COMMAND_TIMEOUT_SECONDS = 0.5
SIDES = ('left', 'right')
DEFAULT_DAC_I2C_ADDRESSES = (0x62, 0x63)
DEFAULT_REVERSE_SWITCH_LINES = (0, 1)


class AnalogThrottleController:
    def __init__(self, dac, reverse_switch_request, reverse_switch_line):
        self.dac = dac
        self.reverse_switch_request = reverse_switch_request
        self.reverse_switch_line = reverse_switch_line

    def write_throttle_code(self, throttle_code):
        self.dac.raw_value = throttle_code

    def set_reverse_switch(self, is_on):
        self.reverse_switch_request.set_value(
            self.reverse_switch_line, Value.ACTIVE if is_on else Value.INACTIVE)


class AnalogThrottleMotorDriver(Node):
    def __init__(self):
        super().__init__('analog_throttle_motor_driver')
        self.declare_parameter('i2c_bus', 1)
        self.declare_parameter('gpio_chip', 0)
        self.declare_parameter('full_scale_wheel_speed', 1.0)
        self.declare_parameter('min_throttle_volts', 0.0)
        self.declare_parameter('max_throttle_volts', 5.0)
        self.declare_parameter('dac_supply_volts', 5.0)
        for side, dac_i2c_address, reverse_switch_line in zip(
                SIDES, DEFAULT_DAC_I2C_ADDRESSES, DEFAULT_REVERSE_SWITCH_LINES):
            self.declare_parameter(f'{side}_dac_i2c_address', dac_i2c_address)
            self.declare_parameter(f'{side}_reverse_switch_line', reverse_switch_line)
            self.declare_parameter(f'{side}_is_reversed', False)

        self.full_scale_wheel_speed = self.get_parameter('full_scale_wheel_speed').value
        throttle_band = ThrottleBand(
            self.get_parameter('min_throttle_volts').value,
            self.get_parameter('max_throttle_volts').value,
            self.get_parameter('dac_supply_volts').value)
        reverse_switch_lines = [
            self.get_parameter(f'{side}_reverse_switch_line').value for side in SIDES]
        self.reverse_switch_request = gpiod.request_lines(
            f'/dev/gpiochip{self.get_parameter("gpio_chip").value}',
            consumer=self.get_name(),
            config={
                reverse_switch_line: gpiod.LineSettings(
                    direction=Direction.OUTPUT, output_value=Value.INACTIVE)
                for reverse_switch_line in reverse_switch_lines
            })
        i2c = ExtendedI2C(self.get_parameter('i2c_bus').value)
        self.wheels = [
            AnalogThrottleWheel(
                AnalogThrottleController(
                    adafruit_mcp4725.MCP4725(
                        i2c, address=self.get_parameter(f'{side}_dac_i2c_address').value),
                    self.reverse_switch_request, reverse_switch_line),
                throttle_band,
                is_reversed=self.get_parameter(f'{side}_is_reversed').value)
            for side, reverse_switch_line in zip(SIDES, reverse_switch_lines)
        ]

        self.commanded_mode = Drive.MODE_NONE
        self.last_command_time = self.get_clock().now()
        self.drive_subscription = self.create_subscription(
            Drive, 'platform/motors/cmd_drive', self.on_drive, qos_profile_sensor_data)
        self.feedback_publisher = self.create_publisher(
            Feedback, 'platform/motors/feedback', qos_profile_sensor_data)
        self.feedback_timer = self.create_timer(1.0 / FEEDBACK_RATE_HZ, self.publish_feedback)

    def on_drive(self, message):
        self.last_command_time = self.get_clock().now()
        self.commanded_mode = message.mode
        if message.mode == Drive.MODE_VELOCITY:
            wheel_speeds = message.drivers
        elif message.mode == Drive.MODE_PWM:
            wheel_speeds = [value * self.full_scale_wheel_speed for value in message.drivers]
        else:
            self.release_throttles()
            return
        for wheel, wheel_speed in zip(self.wheels, cap_arc_wheel_speeds(*wheel_speeds)):
            wheel.drive(float(wheel_speed), self.full_scale_wheel_speed)

    def release_throttles(self):
        for wheel in self.wheels:
            wheel.release_throttle()

    def publish_feedback(self):
        now = self.get_clock().now()
        has_timed_out = now - self.last_command_time > Duration(seconds=COMMAND_TIMEOUT_SECONDS)
        if has_timed_out:
            self.release_throttles()

        message = Feedback()
        message.header.stamp = now.to_msg()
        message.commanded_mode = self.commanded_mode
        message.actual_mode = Drive.MODE_NONE if has_timed_out else self.commanded_mode
        for wheel, driver_feedback in zip(self.wheels, message.drivers):
            wheel.travel += wheel.velocity / FEEDBACK_RATE_HZ
            driver_feedback.duty_cycle = wheel.speed_fraction
            driver_feedback.measured_velocity = wheel.velocity
            driver_feedback.measured_travel = wheel.travel
        self.feedback_publisher.publish(message)


def main():
    rclpy.init()
    node = AnalogThrottleMotorDriver()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.release_throttles()
        node.reverse_switch_request.release()


if __name__ == '__main__':
    main()
