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

# SteadyWin GIM6010-8 joint motor (ODrive-based FOC driver, 8:1 planetary)
# Datasheet: https://www.scribd.com/document/841947985/SteadyWin-GIM6010-8-English-1-1
# Product: https://steadywin.cn/en/h-pd-116.html
# Vendor docs: https://steadywin.cn/en/col.jsp?id=124
# Store: https://steadywin-motor.com/products/built-in-star-gear-motor-motor-robot-joint-driver-actuator-controller-motor
# SVD48V30A servo driver manual: https://www.uumotor.com/en/wp-content/uploads/2022/04/SVD48V30A-user-manual-V2.0.pdf


import math
import time

import odrive
from odrive.enums import (
    AXIS_STATE_CLOSED_LOOP_CONTROL,
    AXIS_STATE_IDLE,
    CONTROL_MODE_VELOCITY_CONTROL,
    INPUT_MODE_PASSTHROUGH,
)
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from robot_platform_msgs.msg import Drive, Feedback


FIND_TIMEOUT_SECONDS = 30.0
NANOSECONDS_PER_SECOND = 1_000_000_000
FEEDBACK_RATE_HZ = 50.0
COMMAND_TIMEOUT_SECONDS = 0.5
WATCHDOG_TIMEOUT_SECONDS = 1.0
REARM_INTERVAL_SECONDS = 1.0
FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ = 25
TURNS_PER_RADIAN = 1.0 / math.tau
VEL_LIMIT_HEADROOM = 1.2


class WheelDriver:
    def __init__(self, device, is_reversed, gear_ratio, max_wheel_speed, logger):
        self.axis = device.axis0
        self.logger = logger
        self.serial = f'{device.serial_number:X}'
        self.direction_sign = -1.0 if is_reversed else 1.0
        self.gear_ratio = gear_ratio
        self.travel_origin_turns = self.axis.encoder.pos_estimate
        self.last_rearm_time = 0.0
        self.current = 0.0
        self.bridge_temperature = 0.0
        self.has_fault = False
        if self.axis.error:
            device.clear_errors()
        controller_config = self.axis.controller.config
        controller_config.control_mode = CONTROL_MODE_VELOCITY_CONTROL
        controller_config.input_mode = INPUT_MODE_PASSTHROUGH
        controller_config.vel_limit = (
            max_wheel_speed * gear_ratio * TURNS_PER_RADIAN
            * VEL_LIMIT_HEADROOM
        )
        self.axis.config.watchdog_timeout = WATCHDOG_TIMEOUT_SECONDS
        self.axis.config.enable_watchdog = True
        self.axis.watchdog_feed()
        self.axis.requested_state = AXIS_STATE_CLOSED_LOOP_CONTROL
        self.device = device

    def rearm_if_tripped(self):
        error_code = self.axis.error
        if not error_code:
            return
        now = time.monotonic()
        if now - self.last_rearm_time < REARM_INTERVAL_SECONDS:
            return
        self.last_rearm_time = now
        self.logger.warning(
            f'motor {self.serial}: cleared axis error {error_code:#x}, '
            f'motor error {self.axis.motor.error:#x}')
        self.device.clear_errors()
        self.axis.watchdog_feed()
        self.axis.requested_state = AXIS_STATE_CLOSED_LOOP_CONTROL

    def drive(self, wheel_speed, max_wheel_speed):
        self.rearm_if_tripped()
        self.axis.watchdog_feed()
        clamped_speed = max(-max_wheel_speed, min(wheel_speed, max_wheel_speed))
        self.axis.controller.input_vel = (
            self.direction_sign * clamped_speed * self.gear_ratio
            * TURNS_PER_RADIAN
        )

    def halt(self):
        self.axis.controller.input_vel = 0.0

    def wheel_radians_from_rotor_turns(self, rotor_turns):
        return self.direction_sign * rotor_turns / self.gear_ratio * math.tau

    def read_slow_telemetry(self):
        self.current = self.axis.motor.current_control.Iq_measured
        self.bridge_temperature = self.axis.motor.fet_thermistor.temperature
        self.has_fault = bool(self.axis.error)

    def release(self):
        self.halt()
        self.axis.config.enable_watchdog = False
        self.axis.requested_state = AXIS_STATE_IDLE


def find_wheels(serials, reversed_flags, gear_ratio, max_wheel_speed, logger):
    devices = odrive.find_sync(count=len(serials), timeout=FIND_TIMEOUT_SECONDS)
    devices_by_serial = {
        f"{device.serial_number:X}": device for device in devices}
    missing_serials = [
        serial for serial in serials if serial not in devices_by_serial]
    if missing_serials:
        raise RuntimeError(
            f"motors {missing_serials} not found, "
            f"connected: {list(devices_by_serial)}")
    return [
        WheelDriver(
            devices_by_serial[serial], is_reversed, gear_ratio,
            max_wheel_speed, logger)
        for serial, is_reversed in zip(serials, reversed_flags)
    ]


class OdriveMotorDriver(Node):
    def __init__(self):
        super().__init__('odrive_motor_driver')
        self.declare_parameter('gear_ratio', 8.0)
        self.declare_parameter('max_wheel_speed', 1.0)
        for side in ('left', 'right'):
            self.declare_parameter(f'{side}_serial', '')
            self.declare_parameter(f'{side}_reversed', False)

        self.max_wheel_speed = self.get_parameter('max_wheel_speed').value
        self.wheels = find_wheels(
            [self.get_parameter(f'{side}_serial').value for side in ('left', 'right')],
            [self.get_parameter(f'{side}_reversed').value for side in ('left', 'right')],
            self.get_parameter('gear_ratio').value,
            self.max_wheel_speed,
            self.get_logger(),
        )
        self.get_logger().info('connected both motors')

        self.commanded_mode = Drive.MODE_NONE
        self.last_command_time = self.get_clock().now()
        self.feedback_tick = 0
        self.drive_subscription = self.create_subscription(
            Drive, 'platform/motors/cmd_drive', self.on_drive,
            qos_profile_sensor_data)
        self.feedback_publisher = self.create_publisher(
            Feedback, 'platform/motors/feedback', qos_profile_sensor_data)
        self.feedback_timer = self.create_timer(
            1.0 / FEEDBACK_RATE_HZ, self.publish_feedback)

    def on_drive(self, message):
        self.last_command_time = self.get_clock().now()
        self.commanded_mode = message.mode
        if message.mode == Drive.MODE_VELOCITY:
            wheel_speeds = message.drivers
        elif message.mode == Drive.MODE_PWM:
            wheel_speeds = [
                value * self.max_wheel_speed for value in message.drivers]
        else:
            for wheel in self.wheels:
                wheel.halt()
            return
        for wheel, wheel_speed in zip(self.wheels, wheel_speeds):
            wheel.drive(float(wheel_speed), self.max_wheel_speed)

    def publish_feedback(self):
        now = self.get_clock().now()
        elapsed_ns = (now - self.last_command_time).nanoseconds
        has_timed_out = (
            elapsed_ns > COMMAND_TIMEOUT_SECONDS * NANOSECONDS_PER_SECOND)
        if has_timed_out:
            for wheel in self.wheels:
                wheel.halt()

        self.feedback_tick += 1
        should_read_slow_telemetry = (
            self.feedback_tick % FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ == 0)

        message = Feedback()
        message.header.stamp = now.to_msg()
        message.commanded_mode = self.commanded_mode
        message.actual_mode = (
            Drive.MODE_NONE if has_timed_out else self.commanded_mode)
        for wheel, driver_feedback in zip(self.wheels, message.drivers):
            if should_read_slow_telemetry:
                wheel.read_slow_telemetry()
            encoder = wheel.axis.encoder
            driver_feedback.measured_velocity = (
                wheel.wheel_radians_from_rotor_turns(encoder.vel_estimate))
            driver_feedback.measured_travel = (
                wheel.wheel_radians_from_rotor_turns(
                    encoder.pos_estimate - wheel.travel_origin_turns))
            driver_feedback.current = wheel.current
            driver_feedback.bridge_temperature = wheel.bridge_temperature
            driver_feedback.driver_fault = wheel.has_fault
        self.feedback_publisher.publish(message)


def main():
    rclpy.init()
    node = OdriveMotorDriver()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        for wheel in node.wheels:
            try:
                wheel.release()
            except Exception:
                pass


if __name__ == '__main__':
    main()
