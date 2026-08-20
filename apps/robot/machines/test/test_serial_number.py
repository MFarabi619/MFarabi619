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

from robot_config.common.definitions.serial_number import SerialNumber


def test_parse_mark_serial():
    assert SerialNumber.parse('mark-0') == ('mark', '0')


def test_parse_is_case_insensitive():
    assert SerialNumber.parse('MARK-1') == ('mark', '1')


def test_serial_number_str_roundtrips():
    assert str(SerialNumber.parse('mark-0')) == 'mark-0'


def test_parse_bare_generic_defaults_unit():
    assert SerialNumber.parse('generic') == ('generic', 'xxxx')


def test_parse_generic_with_unit():
    assert SerialNumber.parse('generic-0001') == ('generic', '0001')


def test_serial_number_splits_model_and_unit():
    serial = SerialNumber.parse('mark-42')
    assert serial.get_model() == 'mark'
    assert serial.get_unit() == '42'


@pytest.mark.parametrize('bad', ['mark', 'mark-abc', 'mark-1-2', 'a-b-c-d'])
def test_invalid_serials_raise_value_error(bad):
    with pytest.raises(ValueError):
        SerialNumber.parse(bad)


def test_non_string_serial_raises_type_error():
    with pytest.raises(TypeError, match='must be string'):
        SerialNumber.parse(1234)
