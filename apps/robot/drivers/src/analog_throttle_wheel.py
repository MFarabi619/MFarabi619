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


from collections import namedtuple
import math

DAC_FULL_SCALE_CODE = 4095
RELEASED_THROTTLE_CODE = 0
RELEASED_BEFORE_START_SECONDS = -math.inf

ThrottleBand = namedtuple(
    'ThrottleBand', ('min_throttle_volts', 'max_throttle_volts', 'dac_supply_volts'))


def throttle_code_from_speed_fraction(speed_fraction, throttle_band):
    if speed_fraction == 0.0:
        return RELEASED_THROTTLE_CODE
    volts = throttle_band.min_throttle_volts + min(abs(speed_fraction), 1.0) * (
        throttle_band.max_throttle_volts - throttle_band.min_throttle_volts)
    return round(min(volts / throttle_band.dac_supply_volts, 1.0) * DAC_FULL_SCALE_CODE)


class AnalogThrottleWheel:
    def __init__(self, controller, throttle_band, reverse_dwell_seconds, *, is_reversed):
        self.controller = controller
        self.throttle_band = throttle_band
        self.reverse_dwell_seconds = reverse_dwell_seconds
        self.is_reversed = is_reversed
        self.is_reverse_switch_on = False
        self.throttle_released_at_seconds = RELEASED_BEFORE_START_SECONDS
        self.last_throttle_code = None
        self.speed_fraction = 0.0
        self.velocity = 0.0
        self.travel = 0.0
        self.write_throttle_code(RELEASED_THROTTLE_CODE)

    def drive(self, wheel_speed, full_scale_wheel_speed, now_seconds):
        if wheel_speed == 0.0:
            self.release_throttle(now_seconds)
            return
        wants_reverse_switch_on = (wheel_speed < 0.0) != self.is_reversed
        if wants_reverse_switch_on != self.is_reverse_switch_on:
            self.release_throttle(now_seconds)
            if now_seconds - self.throttle_released_at_seconds < self.reverse_dwell_seconds:
                return
            self.controller.set_reverse_switch(wants_reverse_switch_on)
            self.is_reverse_switch_on = wants_reverse_switch_on
        self.speed_fraction = max(-1.0, min(wheel_speed / full_scale_wheel_speed, 1.0))
        self.write_throttle_code(
            throttle_code_from_speed_fraction(self.speed_fraction, self.throttle_band))
        self.throttle_released_at_seconds = None
        self.velocity = wheel_speed

    def release_throttle(self, now_seconds):
        self.write_throttle_code(RELEASED_THROTTLE_CODE)
        if self.throttle_released_at_seconds is None:
            self.throttle_released_at_seconds = now_seconds
        self.speed_fraction = 0.0
        self.velocity = 0.0

    def write_throttle_code(self, throttle_code):
        if throttle_code == self.last_throttle_code:
            return
        self.controller.write_throttle_code(throttle_code)
        self.last_throttle_code = throttle_code
