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


import pytest

FULL_SCALE_WHEEL_SPEED = 10.0
HALF_WHEEL_SPEED = FULL_SCALE_WHEEL_SPEED / 2
KELLY_MIN_THROTTLE_VOLTS = 1.0
KELLY_MAX_THROTTLE_VOLTS = 4.0
DAC_SUPPLY_VOLTS = 5.0
MID_BAND_VOLTS = 2.5
VOLTS_TOLERANCE = 0.01


@pytest.fixture
def kelly_band(analog_throttle_wheel_module):
    return analog_throttle_wheel_module.ThrottleBand(
        KELLY_MIN_THROTTLE_VOLTS, KELLY_MAX_THROTTLE_VOLTS, DAC_SUPPLY_VOLTS)


class RecordingAnalogThrottleController:
    def __init__(self):
        self.throttle_codes = []
        self.reverse_switch_states = []
        self.events = []

    def write_throttle_code(self, throttle_code):
        self.throttle_codes.append(throttle_code)
        self.events.append(('throttle', throttle_code))

    def set_reverse_switch(self, is_on):
        self.reverse_switch_states.append(is_on)
        self.events.append(('reverse_switch', is_on))


@pytest.fixture
def controller():
    return RecordingAnalogThrottleController()


@pytest.fixture
def wheel(analog_throttle_wheel_module, controller, kelly_band):
    return analog_throttle_wheel_module.AnalogThrottleWheel(
        controller, kelly_band, is_reversed=False)


@pytest.fixture
def volts_from_throttle_code(analog_throttle_wheel_module):
    def volts_from_throttle_code(throttle_code):
        return throttle_code / analog_throttle_wheel_module.DAC_FULL_SCALE_CODE * DAC_SUPPLY_VOLTS
    return volts_from_throttle_code


@pytest.mark.usefixtures('wheel')
def test_starts_with_the_throttle_released(analog_throttle_wheel_module, controller):
    assert controller.throttle_codes == [analog_throttle_wheel_module.RELEASED_THROTTLE_CODE]


@pytest.mark.parametrize(('speed_fraction', 'expected_volts'), [
    (0.0, 0.0),
    (0.01, 1.03),
    (0.5, MID_BAND_VOLTS),
    (1.0, KELLY_MAX_THROTTLE_VOLTS),
    (2.0, KELLY_MAX_THROTTLE_VOLTS),
    (-1.0, KELLY_MAX_THROTTLE_VOLTS),
])
def test_speed_maps_onto_the_throttle_band(
        analog_throttle_wheel_module, kelly_band, volts_from_throttle_code, speed_fraction,
        expected_volts):
    throttle_code = analog_throttle_wheel_module.throttle_code_from_speed_fraction(
        speed_fraction, kelly_band)
    assert volts_from_throttle_code(throttle_code) == pytest.approx(
        expected_volts, abs=VOLTS_TOLERANCE)


def test_forward_drive_never_touches_the_reverse_switch(
        wheel, controller, volts_from_throttle_code):
    wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    assert controller.reverse_switch_states == []
    assert volts_from_throttle_code(controller.throttle_codes[-1]) == pytest.approx(
        MID_BAND_VOLTS, abs=VOLTS_TOLERANCE)


def test_stop_releases_the_throttle(analog_throttle_wheel_module, wheel, controller):
    wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    wheel.drive(0.0, FULL_SCALE_WHEEL_SPEED)
    assert controller.throttle_codes[-1] == analog_throttle_wheel_module.RELEASED_THROTTLE_CODE


def test_reversing_switches_direction_immediately(
        wheel, controller, volts_from_throttle_code):
    wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    wheel.drive(-HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    assert controller.reverse_switch_states == [True]
    assert volts_from_throttle_code(controller.throttle_codes[-1]) == pytest.approx(
        MID_BAND_VOLTS, abs=VOLTS_TOLERANCE)


def test_reversed_wheel_turns_the_reverse_switch_on_for_forward_travel(
        analog_throttle_wheel_module, controller, kelly_band):
    reversed_wheel = analog_throttle_wheel_module.AnalogThrottleWheel(
        controller, kelly_band, is_reversed=True)
    reversed_wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    assert controller.reverse_switch_states == [True]


def test_unchanged_throttle_is_not_rewritten(wheel, controller):
    wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    wheel.drive(HALF_WHEEL_SPEED, FULL_SCALE_WHEEL_SPEED)
    assert len(controller.throttle_codes) == 2


@pytest.mark.parametrize('left_wheel_speed, right_wheel_speed', [
    (1.0, 1.0), (-1.0, -1.0), (-0.6, 0.6), (0.6, -0.6), (0.0, 0.0)])
def test_straight_and_pivot_wheel_speeds_pass_through(
        analog_throttle_wheel_module, left_wheel_speed, right_wheel_speed):
    assert analog_throttle_wheel_module.cap_arc_wheel_speeds(
        left_wheel_speed, right_wheel_speed) == (left_wheel_speed, right_wheel_speed)


@pytest.mark.parametrize('left_wheel_speed, right_wheel_speed, capped_wheel_speeds', [
    (0.4, 1.6, (0.25, 1.0)),
    (1.6, 0.4, (1.0, 0.25)),
    (-0.4, -1.6, (-0.25, -1.0)),
    (0.0, 1.0, (0.0, 0.5))])
def test_arc_outer_wheel_is_capped_at_the_forward_speed(
        analog_throttle_wheel_module, left_wheel_speed, right_wheel_speed, capped_wheel_speeds):
    assert analog_throttle_wheel_module.cap_arc_wheel_speeds(
        left_wheel_speed, right_wheel_speed) == pytest.approx(capped_wheel_speeds)
