#!/usr/bin/env python3

import os
import time

import gpiod
import rclpy
from gpiod.line import Direction, Value
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from robot_platform_msgs.msg import Drive, Feedback


PWM_EXPORT_RETRIES = 500
PWM_EXPORT_RETRY_DELAY_SECONDS = 0.01
NANOSECONDS_PER_SECOND = 1_000_000_000
FEEDBACK_RATE_HZ = 50.0
COMMAND_TIMEOUT_SECONDS = 0.5


def write_sysfs(path, value):
    with open(path, 'w') as file:
        file.write(value)


class PwmChannel:
    def __init__(self, chip, channel, period_ns):
        self.period_ns = period_ns
        self.channel_path = f'/sys/class/pwm/pwmchip{chip}/pwm{channel}'
        duty_path = f'{self.channel_path}/duty_cycle'
        if not os.access(self.channel_path, os.F_OK):
            write_sysfs(f'/sys/class/pwm/pwmchip{chip}/export', str(channel))
        for _ in range(PWM_EXPORT_RETRIES):
            if os.access(duty_path, os.W_OK):
                break
            time.sleep(PWM_EXPORT_RETRY_DELAY_SECONDS)
        write_sysfs(duty_path, '0')
        write_sysfs(f'{self.channel_path}/period', str(period_ns))
        write_sysfs(f'{self.channel_path}/enable', '1')
        self.duty_file = open(duty_path, 'w')
        self.last_duty_ns = 0

    def write_duty_ns(self, duty_ns):
        if duty_ns == self.last_duty_ns:
            return
        self.duty_file.seek(0)
        self.duty_file.write(str(duty_ns))
        self.duty_file.flush()
        self.last_duty_ns = duty_ns

    def close(self):
        self.write_duty_ns(0)
        write_sysfs(f'{self.channel_path}/enable', '0')
        self.duty_file.close()


class WheelDriver:
    def __init__(self, dir_request, pwm_chip, pwm_channel, dir_pin,
                 forward_level, period_ns):
        self.dir_request = dir_request
        self.dir_pin = dir_pin
        self.forward_level = forward_level
        self.pwm = PwmChannel(pwm_chip, pwm_channel, period_ns)
        self.last_dir_level = None
        self.duty_fraction = 0.0
        self.velocity = 0.0
        self.travel = 0.0

    def drive(self, wheel_speed, max_wheel_speed):
        dir_level = 1 if (wheel_speed >= 0.0) == self.forward_level else 0
        if dir_level != self.last_dir_level:
            self.dir_request.set_value(
                self.dir_pin, Value.ACTIVE if dir_level else Value.INACTIVE)
            self.last_dir_level = dir_level
        duty_fraction = min(abs(wheel_speed) / max_wheel_speed, 1.0)
        self.pwm.write_duty_ns(int(duty_fraction * self.pwm.period_ns))
        self.duty_fraction = (
            duty_fraction if wheel_speed >= 0.0 else -duty_fraction)
        self.velocity = wheel_speed

    def halt(self):
        self.pwm.write_duty_ns(0)
        self.duty_fraction = 0.0
        self.velocity = 0.0


class CytronMotorDriver(Node):
    def __init__(self):
        super().__init__('cytron_motor_driver')
        self.declare_parameter('gpio_chip', 0)
        self.declare_parameter('pwm_frequency_hz', 20000.0)
        self.declare_parameter('max_wheel_speed', 1.0)
        for side in ('left', 'right'):
            self.declare_parameter(f'{side}_pwm_chip', 0)
            self.declare_parameter(f'{side}_pwm_channel', 0)
            self.declare_parameter(f'{side}_dir_pin', 0)
            self.declare_parameter(f'{side}_forward_level', True)

        self.max_wheel_speed = self.get_parameter('max_wheel_speed').value
        period_ns = int(
            NANOSECONDS_PER_SECOND / self.get_parameter('pwm_frequency_hz').value)
        dir_pins = [
            self.get_parameter(f'{side}_dir_pin').value
            for side in ('left', 'right')
        ]
        self.dir_request = gpiod.request_lines(
            f'/dev/gpiochip{self.get_parameter("gpio_chip").value}',
            consumer='cytron_motor_driver',
            config={
                dir_pin: gpiod.LineSettings(
                    direction=Direction.OUTPUT, output_value=Value.INACTIVE)
                for dir_pin in dir_pins
            })
        self.wheels = [
            WheelDriver(
                self.dir_request,
                self.get_parameter(f'{side}_pwm_chip').value,
                self.get_parameter(f'{side}_pwm_channel').value,
                dir_pin,
                self.get_parameter(f'{side}_forward_level').value,
                period_ns)
            for side, dir_pin in zip(('left', 'right'), dir_pins)
        ]

        self.commanded_mode = Drive.MODE_NONE
        self.last_command_time = self.get_clock().now()
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
            wheel.drive(wheel_speed, self.max_wheel_speed)

    def publish_feedback(self):
        now = self.get_clock().now()
        elapsed_ns = (now - self.last_command_time).nanoseconds
        has_timed_out = (
            elapsed_ns > COMMAND_TIMEOUT_SECONDS * NANOSECONDS_PER_SECOND)
        if has_timed_out:
            for wheel in self.wheels:
                wheel.halt()

        message = Feedback()
        message.header.stamp = now.to_msg()
        message.commanded_mode = self.commanded_mode
        message.actual_mode = (
            Drive.MODE_NONE if has_timed_out else self.commanded_mode)
        for wheel, driver_feedback in zip(self.wheels, message.drivers):
            wheel.travel += wheel.velocity / FEEDBACK_RATE_HZ
            driver_feedback.duty_cycle = wheel.duty_fraction
            driver_feedback.measured_velocity = wheel.velocity
            driver_feedback.measured_travel = wheel.travel
        self.feedback_publisher.publish(message)


def main():
    rclpy.init()
    node = CytronMotorDriver()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        for wheel in node.wheels:
            wheel.halt()
            wheel.pwm.close()
        node.dir_request.release()


if __name__ == '__main__':
    main()
