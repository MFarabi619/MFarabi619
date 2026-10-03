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


import math

import pytest
from rclpy.duration import Duration

from robot_platform_msgs.msg import Drive


def command(mode, drivers):
    message = Drive()
    message.mode = mode
    message.drivers = [float(value) for value in drivers]
    return message


def capture(node):
    messages = []
    node.feedback_publisher.publish = messages.append
    return messages


def test_connect_disables_echo(make_roboteq_driver):
    _, port = make_roboteq_driver()
    assert port.written[0] == b'^ECHOF 1\r'


def test_velocity_command_sends_rpm_per_channel(make_roboteq_driver):
    node, port = make_roboteq_driver()
    node.on_drive(command(Drive.MODE_VELOCITY, [math.tau, -math.tau]))
    assert b'!S 1 60\r' in port.written
    assert b'!S 2 -60\r' in port.written


def test_velocity_command_clamps_to_max_wheel_speed(make_roboteq_driver):
    node, port = make_roboteq_driver(max_wheel_speed=math.tau)
    node.on_drive(command(Drive.MODE_VELOCITY, [2 * math.tau, 0.0]))
    assert b'!S 1 60\r' in port.written


def test_without_max_wheel_speed_commands_are_unclamped(make_roboteq_driver):
    node, port = make_roboteq_driver(max_wheel_speed=None)
    node.on_drive(command(Drive.MODE_VELOCITY, [100 * math.tau, 0.0]))
    assert b'!S 1 6000\r' in port.written


def test_torque_mode_reads_full_scale_rpm_at_connect(make_roboteq_driver):
    node, port = make_roboteq_driver(
        control_mode='torque', connect_replies=[b'MXRPM=3000:1500\r'])
    assert node.full_scale_rpm == [3000, 1500]
    assert b'~MXRPM\r' in port.written


def test_torque_mode_scales_velocity_to_torque_fraction(make_roboteq_driver):
    node, port = make_roboteq_driver(
        control_mode='torque', max_wheel_speed=None,
        connect_replies=[b'MXRPM=3000:3000\r'])
    node.on_drive(command(Drive.MODE_VELOCITY, [25 * math.tau, -50 * math.tau]))
    assert b'!G 1 500\r' in port.written
    assert b'!G 2 -1000\r' in port.written


def test_torque_mode_timeout_commands_zero_torque(make_roboteq_driver):
    node, port = make_roboteq_driver(
        control_mode='torque', connect_replies=[b'MXRPM=3000:3000\r'])
    messages = capture(node)
    node.last_command_time -= Duration(seconds=1.0)
    port.read_queue = list(IDLE_FAST_REPLIES)
    node.publish_feedback()
    assert b'!G 1 0\r' in port.written
    assert b'!G 2 0\r' in port.written
    assert messages[0].actual_mode == Drive.MODE_NONE


def test_pwm_command_clamps_to_full_power(make_roboteq_driver):
    node, port = make_roboteq_driver()
    node.on_drive(command(Drive.MODE_PWM, [0.5, -2.0]))
    assert b'!G 1 500\r' in port.written
    assert b'!G 2 -1000\r' in port.written


def test_mode_none_stops_both_wheels(make_roboteq_driver):
    node, port = make_roboteq_driver()
    node.on_drive(command(Drive.MODE_NONE, [0.0, 0.0]))
    assert b'!S 1 0\r' in port.written
    assert b'!S 2 0\r' in port.written


def test_reversed_side_flips_command_sign(make_roboteq_driver):
    node, port = make_roboteq_driver(left_reversed=True)
    node.on_drive(command(Drive.MODE_VELOCITY, [math.tau, math.tau]))
    assert b'!S 1 -60\r' in port.written
    assert b'!S 2 60\r' in port.written


FAST_REPLIES = [b'BS=120:-60\r', b'CB=900:-450\r', b'P=500:-250\r']
IDLE_FAST_REPLIES = [b'BS=0:0\r', b'CB=0:0\r', b'P=0:0\r']
SLOW_REPLIES = [
    b'A=52:-48\r', b'T=35:40:41\r', b'FF=16\r', b'FS=16\r',
    b'V=135:246:4730\r', b'BA=31:-29\r', b'E=12:-8\r', b'FM=2:0\r',
    b'SEC=3:0\r', b'DPA=61:55\r', b'MA=2:30:-1:-27\r']


def capture_diagnostics(node):
    messages = []
    node.diagnostics_publisher.publish = messages.append
    return messages


def test_feedback_reports_wheel_motion_in_radians(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    port.read_queue = list(FAST_REPLIES)
    node.publish_feedback()
    left, right = messages[0].drivers
    assert left.measured_velocity == pytest.approx(2 * math.tau)
    assert right.measured_velocity == pytest.approx(-math.tau)
    assert left.measured_travel == pytest.approx(10 * math.tau)
    assert right.measured_travel == pytest.approx(-5 * math.tau)


def test_duty_cycle_reports_applied_power(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    port.read_queue = list(FAST_REPLIES)
    node.publish_feedback()
    left, right = messages[0].drivers
    assert left.duty_cycle == pytest.approx(0.5)
    assert right.duty_cycle == pytest.approx(-0.25)


def test_ack_lines_are_skipped_before_query_reply(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    port.read_queue = [b'+\r', b'BS=0:0\r', b'+\r', b'CB=0:0\r', b'P=0:0\r']
    node.publish_feedback()
    assert messages[0].drivers[0].measured_velocity == 0.0


def test_serial_silence_skips_publish(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    node.publish_feedback()
    assert messages == []


def test_command_timeout_zeroes_the_motors(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    node.last_command_time -= Duration(seconds=1.0)
    port.read_queue = list(IDLE_FAST_REPLIES)
    node.publish_feedback()
    assert b'!S 1 0\r' in port.written
    assert b'!S 2 0\r' in port.written
    assert messages[0].actual_mode == Drive.MODE_NONE


def test_fault_flags_mark_both_drivers_faulted(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    node.feedback_tick = node.FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ - 1
    port.read_queue = list(IDLE_FAST_REPLIES) + list(SLOW_REPLIES)
    node.publish_feedback()
    left, right = messages[0].drivers
    assert left.driver_fault and right.driver_fault
    assert left.current == pytest.approx(5.2)
    assert right.current == pytest.approx(-4.8)
    assert left.bridge_temperature == pytest.approx(40.0)
    assert right.bridge_temperature == pytest.approx(41.0)


def test_diagnostics_report_volts_amps_and_loop_error(make_roboteq_driver):
    node, port = make_roboteq_driver()
    capture(node)
    diagnostics = capture_diagnostics(node)
    node.feedback_tick = node.FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ - 1
    port.read_queue = list(IDLE_FAST_REPLIES) + list(SLOW_REPLIES)
    node.publish_feedback()
    controller, channel_1, channel_2 = diagnostics[0].status
    values = {entry.key: entry.value for entry in controller.values}
    assert values['battery_volts'] == '24.6'
    assert values['internal_volts'] == '13.5'
    assert values['five_volt_rail'] == '4.73'
    assert values['mcu_temperature'] == '35.0'
    channel_1_values = {entry.key: entry.value for entry in channel_1.values}
    assert channel_1_values['battery_amps'] == '3.1'
    assert channel_1_values['loop_error_rpm'] == '12'
    assert channel_1_values['hall_sensor_errors'] == '3'
    assert channel_1_values['peak_amps'] == '6.1'
    assert channel_1_values['foc_flux_amps'] == '0.2'
    assert channel_1_values['foc_torque_amps'] == '3.0'
    assert 'motor stalled' in channel_1.message
    assert channel_2.values[0].key == 'motor_amps'


def test_power_stage_off_warns_on_controller_status(make_roboteq_driver):
    node, port = make_roboteq_driver()
    capture(node)
    diagnostics = capture_diagnostics(node)
    node.feedback_tick = node.FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ - 1
    replies = [
        b'A=0:0\r', b'T=25:30:31\r', b'FF=0\r', b'FS=8\r',
        b'V=135:246:4730\r', b'BA=0:0\r', b'E=0:0\r', b'FM=0:0\r',
        b'SEC=0:0\r', b'DPA=0:0\r', b'MA=0:0:0:0\r']
    port.read_queue = list(IDLE_FAST_REPLIES) + replies
    node.publish_feedback()
    controller = diagnostics[0].status[0]
    assert controller.level == controller.WARN
    assert 'power stage off' in controller.message


def test_short_temperature_reply_warns_instead_of_crashing(make_roboteq_driver):
    node, port = make_roboteq_driver()
    messages = capture(node)
    node.feedback_tick = node.FEEDBACK_TICKS_PER_SLOW_TELEMETRY_READ - 1
    port.read_queue = list(IDLE_FAST_REPLIES) + [b'A=0:0\r', b'T=25\r']
    node.publish_feedback()
    assert messages == []
