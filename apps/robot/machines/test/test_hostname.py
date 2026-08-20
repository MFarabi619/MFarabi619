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

from robot_config.common.definitions.hostname import Hostname

VALID_HOSTNAMES = ['beagleyai', 'robot-0', 'a', 'host.domain', 'A1-b2', 'x' * 63]
INVALID_HOSTNAMES = ['-host', 'host-', 'host_name', 'host.', 'x' * 64, 'a..b', 'робот']


@pytest.mark.parametrize('hostname', VALID_HOSTNAMES)
def test_valid_hostnames_pass(hostname):
    assert Hostname.is_valid(hostname)
    assert str(Hostname(hostname)) == hostname


@pytest.mark.parametrize('hostname', INVALID_HOSTNAMES)
def test_invalid_hostnames_rejected(hostname):
    assert not Hostname.is_valid(hostname)
    with pytest.raises(ValueError):
        Hostname.assert_valid(hostname)


def test_blank_hostname_raises_value_error():
    with pytest.raises(ValueError, match='blank'):
        Hostname.assert_valid('')


def test_over_length_hostname_raises_value_error():
    with pytest.raises(ValueError, match='253'):
        Hostname.assert_valid('x' * 254)


def test_non_string_hostname_raises_type_error():
    with pytest.raises(TypeError, match='str'):
        Hostname.assert_valid(123)


def test_hostname_equality():
    assert Hostname('beagleyai') == 'beagleyai'
    assert Hostname('beagleyai') == Hostname('beagleyai')
    assert Hostname('beagleyai') != 'other'
