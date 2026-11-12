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


LONGITUDINAL_WORDS = {
    'forward': 1.0, 'straight': 1.0, 'backward': -1.0, 'back': -1.0,
}
STEER_WORDS = {'left': 1.0, 'right': -1.0}
PIVOT_WORDS = {'clockwise': -1.0, 'counterclockwise': 1.0}
DIGIT_WORDS = {
    'zero': 0.0, 'one': 1.0, 'two': 2.0,
    'three': 3.0, 'four': 4.0, 'five': 5.0,
}
SPEED_PARAMETER_WORDS = {
    'linear': 'forward_speed_meters_per_second',
    'angular': 'angular_speed_radians_per_second',
}
TELEOP_WORDS = frozenset(
    ['stop', *LONGITUDINAL_WORDS, *STEER_WORDS, *PIVOT_WORDS, *DIGIT_WORDS,
     *SPEED_PARAMETER_WORDS])
