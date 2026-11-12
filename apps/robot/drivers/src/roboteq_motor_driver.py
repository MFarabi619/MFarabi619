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

# Roboteq SBLMG2360T dual brushless controller (ASCII serial over USB or RS232)
# Datasheet and manual: assets/roboteq-sblmg2360t-gen-4-*.pdf


import math

from diagnostic_msgs.msg import DiagnosticArray, DiagnosticStatus, KeyValue
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
import serial
from std_msgs.msg import Header
from std_srvs.srv import Trigger

from robot_platform_msgs.msg import Drive, Feedback


FEEDBACK_RATE_HZ = 50.0
COMMAND_TIMEOUT_SECONDS = 0.5
SERIAL_TIMEOUT_SECONDS = 0.1
RPM_PER_RADIAN_PER_SECOND = 60.0 / math.tau
FULL_POWER_COMMAND = 1000
QUERY_READ_MAX_ATTEMPTS = 5
TENTHS_PER_UNIT = 10.0
FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ = 25

THOUSANDTHS_PER_UNIT = 1000.0

CONFIGURATION_CODES = (
    'MMOD', 'ALIM', 'ATRIG', 'ATGD', 'ATGA', 'THLD', 'MXPF', 'MXPR',
    'MAC', 'MDEC', 'MXRPM', 'MNRPM', 'TNM', 'NOMA', 'TPAL',
    'KPF', 'KIF', 'KPG', 'KIG', 'KDG', 'KP', 'KI', 'KD', 'BLFB',
    'MDIR', 'PMOD', 'PINA', 'PPOL', 'PMIN', 'PMAX', 'RWD', 'OVL', 'UVL')

FAULT_BIT_NAMES = {
    0: 'overheat',
    1: 'overvoltage',
    2: 'undervoltage',
    3: 'short circuit',
    4: 'emergency stop',
    5: 'motor/sensor setup fault',
    6: 'MOSFET failure',
    7: 'default configuration loaded',
}

RUNTIME_BIT_NAMES = {
    0: 'amps limit active',
    1: 'motor stalled',
    2: 'loop error',
    3: 'safety stop active',
    4: 'forward limit triggered',
    5: 'reverse limit triggered',
    6: 'amps trigger activated',
}

STATUS_BIT_NAMES = {
    3: 'power stage off',
    4: 'stall detected',
    5: 'at limit',
    8: 'motor/sensor tuning mode',
}

MOSFET_FAILURE_BIT = 6


def decode_bits(bit_names, flags):
    return ', '.join(
        name for bit, name in bit_names.items() if flags & (1 << bit))


def decode_fault_bits(fault_flags):
    return decode_bits(FAULT_BIT_NAMES, fault_flags)


def pair(values):
    return (list(values) + [0, 0])[:2]


class RoboteqBus:
    def __init__(self, port, baud_rate):
        self.port = serial.Serial(port, baud_rate, timeout=SERIAL_TIMEOUT_SECONDS)
        self.port.write(b'^ECHOF 1\r')
        self.port.reset_input_buffer()

    def write_command(self, command):
        self.port.write(f'{command}\r'.encode('ascii'))

    def query_text(self, code, argument=None):
        self.port.reset_input_buffer()
        request = f'?{code}' if argument is None else f'?{code} {argument}'
        self.port.write(f'{request}\r'.encode('ascii'))
        prefix = f'{code}='
        for _ in range(QUERY_READ_MAX_ATTEMPTS):
            line = self.port.read_until(b'\r').decode('ascii', 'replace').strip()
            if line.startswith(prefix):
                return line[len(prefix):]
        raise TimeoutError(f'no reply to {request}')

    def query_configuration(self, code, minimum_values=1, argument=None):
        self.port.reset_input_buffer()
        request = f'~{code}' if argument is None else f'~{code} {argument}'
        self.port.write(f'{request}\r'.encode('ascii'))
        prefix = f'{code}='
        for _ in range(QUERY_READ_MAX_ATTEMPTS):
            line = self.port.read_until(b'\r').decode('ascii', 'replace').strip()
            if line.startswith(prefix):
                values = [int(value) for value in line[len(prefix):].split(':')]
                if len(values) < minimum_values:
                    raise ValueError(
                        f'~{code} reply {line!r} has {len(values)} values, '
                        f'expected {minimum_values}')
                return values
        raise TimeoutError(f'no reply to ~{code}')

    def query(self, code, minimum_values=1, argument=None):
        reply = self.query_text(code, argument)
        values = [int(value) for value in reply.split(':')]
        if len(values) < minimum_values:
            raise ValueError(
                f'?{code} reply {reply!r} has {len(values)} values, '
                f'expected {minimum_values}')
        return values

    def close(self):
        self.port.close()


class RoboteqMotorDriver(Node):
    def __init__(self, **node_arguments):
        super().__init__('roboteq_motor_driver', **node_arguments)
        self.declare_parameter('serial_port', '/dev/ttyACM0')
        self.declare_parameter('baud_rate', 115200)
        self.declare_parameter('counts_per_revolution', 90)
        self.declare_parameter('max_wheel_speed', math.inf)
        self.declare_parameter('control_mode', 'speed')
        self.declare_parameter('full_scale_wheel_speed', 0.0)
        self.declare_parameter('flash', [''])
        for side in ('left', 'right'):
            self.declare_parameter(f'{side}_is_reversed', False)

        self.max_wheel_speed = self.get_parameter('max_wheel_speed').value
        self.counts_per_revolution = self.get_parameter(
            'counts_per_revolution').value
        self.direction_signs = [
            -1.0 if self.get_parameter(f'{side}_is_reversed').value else 1.0
            for side in ('left', 'right')
        ]
        self.bus = RoboteqBus(
            self.get_parameter('serial_port').value,
            self.get_parameter('baud_rate').value,
        )
        self.assert_flash_configuration()
        self.control_mode = self.get_parameter('control_mode').value
        self.commands_fractions = self.control_mode in ('torque', 'open_loop')
        full_scale_wheel_speed = self.get_parameter(
            'full_scale_wheel_speed').value
        if full_scale_wheel_speed > 0.0:
            self.full_scale_wheel_speeds = [
                full_scale_wheel_speed, full_scale_wheel_speed]
        elif self.commands_fractions:
            self.full_scale_wheel_speeds = [
                rpm / RPM_PER_RADIAN_PER_SECOND
                for rpm in pair(self.bus.query_configuration('MXRPM', 2))
            ]
        else:
            self.full_scale_wheel_speeds = [0.0, 0.0]
        self.last_fault_flags = 0
        self.currents = [0.0, 0.0]
        self.mcu_temperature = 0.0
        self.bridge_temperatures = [0.0, 0.0]
        self.feedback_tick = 0
        try:
            self.get_logger().info(
                f'connected {self.bus.query_text("TRN")}'
                f' firmware {self.bus.query_text("FID")}')
        except TimeoutError:
            self.get_logger().info('connected, identity queries unanswered')

        self.diagnostics_publisher = self.create_publisher(
            DiagnosticArray, 'diagnostics', 10)

        self.commanded_mode = Drive.MODE_NONE
        self.motors_stopped = False
        self.last_command_time = self.get_clock().now()
        self.drive_subscription = self.create_subscription(
            Drive, 'platform/motors/cmd_drive', self.on_drive,
            qos_profile_sensor_data)
        self.feedback_publisher = self.create_publisher(
            Feedback, 'platform/motors/feedback', qos_profile_sensor_data)
        self.feedback_timer = self.create_timer(
            1.0 / FEEDBACK_RATE_HZ, self.publish_feedback)

        self.configuration_snapshot = {}
        self.read_configuration_snapshot()
        self.refresh_configuration_service = self.create_service(
            Trigger, 'platform/motors/refresh_configuration',
            self.on_refresh_configuration)

    def read_configuration_snapshot(self):
        for code in CONFIGURATION_CODES:
            try:
                values = self.bus.query_configuration(code)
                self.configuration_snapshot[code] = ':'.join(
                    str(value) for value in values)
            except (TimeoutError, ValueError):
                self.configuration_snapshot.setdefault(code, 'unavailable')

    def on_refresh_configuration(self, request, response):
        self.read_configuration_snapshot()
        read = sum(
            1 for value in self.configuration_snapshot.values()
            if value != 'unavailable')
        response.success = read > 0
        response.message = f'{read}/{len(CONFIGURATION_CODES)} values read'
        return response

    def read_flash_value(self, declaration):
        code, *arguments = declaration
        channel = arguments[0] if len(arguments) == 2 else None
        return self.bus.query_configuration(code, argument=channel)[0]

    def assert_flash_configuration(self):
        declarations = [
            entry.split()
            for entry in self.get_parameter('flash').value
            if entry.strip()
        ]
        drifted = [
            declaration for declaration in declarations
            if self.read_flash_value(declaration) != int(declaration[-1])
        ]
        if not drifted:
            return
        for declaration in drifted:
            self.bus.write_command('^' + ' '.join(declaration))
            self.get_logger().warning(
                f'flash configuration corrected: {" ".join(declaration)}')
        self.bus.write_command('%EESAV')
        rejected = [
            ' '.join(declaration) for declaration in drifted
            if self.read_flash_value(declaration) != int(declaration[-1])
        ]
        if rejected:
            raise RuntimeError(
                f'controller rejected flash configuration: '
                f'{", ".join(rejected)}')

    def rpm_from_wheel_speed(self, wheel_speed, direction_sign):
        clamped_speed = max(
            -self.max_wheel_speed, min(wheel_speed, self.max_wheel_speed))
        return int(direction_sign * clamped_speed * RPM_PER_RADIAN_PER_SECOND)

    def command_velocities(self, wheel_speeds):
        if self.commands_fractions:
            self.command_fractions(wheel_speeds)
        else:
            self.command_speeds(wheel_speeds)

    def command_speeds(self, wheel_speeds):
        for channel, (wheel_speed, direction_sign) in enumerate(
                zip(wheel_speeds, self.direction_signs), start=1):
            self.bus.write_command(
                f'!S {channel} '
                f'{self.rpm_from_wheel_speed(wheel_speed, direction_sign)}')

    def command_fractions(self, wheel_speeds):
        for channel, (wheel_speed, direction_sign) in enumerate(
                zip(wheel_speeds, self.direction_signs), start=1):
            clamped_speed = direction_sign * max(
                -self.max_wheel_speed,
                min(wheel_speed, self.max_wheel_speed))
            fraction = int(max(
                -FULL_POWER_COMMAND,
                min(clamped_speed * FULL_POWER_COMMAND
                    / self.full_scale_wheel_speeds[channel - 1],
                    FULL_POWER_COMMAND)))
            self.bus.write_command(f'!G {channel} {fraction}')

    def command_powers(self, power_fractions):
        for channel, (power_fraction, direction_sign) in enumerate(
                zip(power_fractions, self.direction_signs), start=1):
            power = int(direction_sign * max(
                -FULL_POWER_COMMAND,
                min(power_fraction * FULL_POWER_COMMAND, FULL_POWER_COMMAND)))
            self.bus.write_command(f'!G {channel} {power}')

    def send_drive_command(self, send, values):
        # A repeated stop is withheld so the serial watchdog (RWD) can
        # expire and hand control to the RC pulse inputs.
        is_stop = all(value == 0.0 for value in values)
        if is_stop and self.motors_stopped:
            return
        self.motors_stopped = is_stop
        send(values)

    def on_drive(self, message):
        self.last_command_time = self.get_clock().now()
        self.commanded_mode = message.mode
        if message.mode == Drive.MODE_VELOCITY:
            self.send_drive_command(
                self.command_velocities,
                [float(value) for value in message.drivers])
        elif message.mode == Drive.MODE_PWM:
            self.send_drive_command(
                self.command_powers,
                [float(value) for value in message.drivers])
        else:
            self.send_drive_command(self.command_velocities, [0.0, 0.0])

    def read_slow_telemetry(self, stamp):
        self.currents = [
            value / TENTHS_PER_UNIT for value in self.bus.query('A', 2)]
        temperatures = self.bus.query('T', 2)
        if len(temperatures) > 2:
            self.mcu_temperature = float(temperatures[0])
        self.bridge_temperatures = [
            float(value) for value in temperatures[-2:]]
        fault_flags = self.bus.query('FF')[0]
        if fault_flags != self.last_fault_flags:
            self.last_fault_flags = fault_flags
            if fault_flags:
                self.get_logger().warning(
                    f'fault {fault_flags:#x}: {decode_fault_bits(fault_flags)}')
            if fault_flags & (1 << MOSFET_FAILURE_BIT):
                self.get_logger().error(
                    'MOSFET damage map (STO self test): '
                    f'{self.bus.query("STT", argument=2)[0]:#x}')
        status_flags = self.bus.query('FS')[0]
        volts = self.bus.query('V', 3)
        battery_amperes = [
            value / TENTHS_PER_UNIT for value in self.bus.query('BA', 2)]
        loop_errors = pair(self.bus.query('E'))
        runtime_flags = pair(self.bus.query('FM'))
        sensor_errors = pair(self.bus.query('SEC'))
        peak_amperes = [
            value / TENTHS_PER_UNIT for value in self.bus.query('DPA', 2)]
        foc_amperes = [
            value / TENTHS_PER_UNIT
            for value in (self.bus.query('MA') + [0, 0, 0, 0])[:4]]
        self.publish_diagnostics(
            stamp, fault_flags, status_flags, volts, battery_amperes,
            loop_errors, runtime_flags, sensor_errors, peak_amperes, foc_amperes)

    def publish_diagnostics(
            self, stamp, fault_flags, status_flags, volts, battery_amperes,
            loop_errors, runtime_flags, sensor_errors, peak_amperes, foc_amperes):
        status_message = decode_bits(STATUS_BIT_NAMES, status_flags)
        controller = DiagnosticStatus(
            name='roboteq: controller',
            level=(DiagnosticStatus.ERROR if fault_flags
                   else DiagnosticStatus.WARN if status_message
                   else DiagnosticStatus.OK),
            message=decode_fault_bits(fault_flags) or status_message or 'ok',
            values=[
                KeyValue(key='battery_volts',
                         value=str(volts[1] / TENTHS_PER_UNIT)),
                KeyValue(key='internal_volts',
                         value=str(volts[0] / TENTHS_PER_UNIT)),
                KeyValue(key='five_volt_rail',
                         value=str(volts[2] / THOUSANDTHS_PER_UNIT)),
                KeyValue(key='mcu_temperature',
                         value=str(self.mcu_temperature)),
                KeyValue(key='fault_flags', value=hex(fault_flags)),
            ])
        channels = []
        for index in range(2):
            flags = runtime_flags[index]
            channels.append(DiagnosticStatus(
                name=f'roboteq: channel {index + 1}',
                level=(DiagnosticStatus.WARN if flags or sensor_errors[index]
                       else DiagnosticStatus.OK),
                message=decode_bits(RUNTIME_BIT_NAMES, flags) or 'ok',
                values=[
                    KeyValue(key='motor_amperes',
                             value=str(self.currents[index])),
                    KeyValue(key='battery_amperes',
                             value=str(battery_amperes[index])),
                    KeyValue(key='loop_error_rpm',
                             value=str(loop_errors[index])),
                    KeyValue(key='hall_sensor_errors',
                             value=str(sensor_errors[index])),
                    KeyValue(key='peak_amperes',
                             value=str(peak_amperes[index])),
                    KeyValue(key='foc_flux_amperes',
                             value=str(foc_amperes[2 * index])),
                    KeyValue(key='foc_torque_amperes',
                             value=str(foc_amperes[2 * index + 1])),
                    KeyValue(key='bridge_temperature',
                             value=str(self.bridge_temperatures[index])),
                ]))
        configuration = DiagnosticStatus(
            name='roboteq: configuration',
            level=DiagnosticStatus.OK,
            message='ok',
            values=[
                KeyValue(key=code, value=self.configuration_snapshot[code])
                for code in CONFIGURATION_CODES
            ])
        self.diagnostics_publisher.publish(DiagnosticArray(
            header=Header(stamp=stamp),
            status=[controller, *channels, configuration]))

    def publish_feedback(self):
        now = self.get_clock().now()
        has_timed_out = (
            now - self.last_command_time
            > Duration(seconds=COMMAND_TIMEOUT_SECONDS))
        if has_timed_out:
            self.send_drive_command(self.command_velocities, [0.0, 0.0])

        self.feedback_tick += 1
        try:
            speeds_rpm = self.bus.query('BS', 2)
            hall_counts = self.bus.query('CB', 2)
            applied_powers = self.bus.query('P', 2)
            if self.feedback_tick % FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ == 0:
                self.read_slow_telemetry(now.to_msg())
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
            driver_feedback.measured_travel = (
                direction_sign * hall_counts[motor_index]
                / self.counts_per_revolution * math.tau
            )
            driver_feedback.duty_cycle = (
                direction_sign * applied_powers[motor_index]
                / FULL_POWER_COMMAND
            )
            driver_feedback.current = self.currents[motor_index]
            driver_feedback.bridge_temperature = (
                self.bridge_temperatures[motor_index])
            driver_feedback.driver_fault = self.last_fault_flags != 0
        self.feedback_publisher.publish(message)

    def release(self):
        self.command_velocities([0.0, 0.0])
        self.bus.close()


def main():
    rclpy.init()
    node = RoboteqMotorDriver()
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
