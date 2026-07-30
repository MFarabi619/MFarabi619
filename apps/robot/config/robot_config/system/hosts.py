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


from typing import List

from robot_config.common.definitions.config import BaseConfig
from robot_config.common.definitions.hostname import Hostname
from robot_config.common.definitions.ip import IP
from robot_config.common.definitions.list import ListConfig
from robot_config.common.utils.dictionary import flip_dict


# HostConfig
# - this is the format for which each host involved in the system will be described
class HostConfig(BaseConfig):

    HOSTNAME = 'hostname'
    IP_ADDRESS = 'ip'

    TEMPLATE = {
        HOSTNAME: HOSTNAME,
        IP_ADDRESS: IP_ADDRESS
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS = {
        HOSTNAME: BaseConfig.get_serial_number(),
        IP_ADDRESS: '192.168.131.1',
    }

    def __init__(
            self,
            config: dict = {},
            hostname: str | Hostname = DEFAULTS[HOSTNAME],
            ip_address: str | IP = DEFAULTS[IP_ADDRESS],
            ) -> None:
        # Initialization
        self.hostname = hostname
        self.ip_address = ip_address
        # Setter Template
        setters = {
            self.KEYS[self.HOSTNAME]: HostConfig.hostname,
            self.KEYS[self.IP_ADDRESS]: HostConfig.ip_address,
        }
        # Set from Config
        super().__init__(setters, config, None)

    def __eq__(self, other) -> bool:
        return self.hostname == other.hostname and self.ip_address == other.ip_address

    def __str__(self) -> str:
        return '{ hostname: %s, ip: %s }' % (str(self.hostname), str(self.ip_address))

    def to_dict(self) -> dict:
        return {str(self.hostname): str(self.ip_address)}

    # Hostname:
    # - the hostname of the computer
    @property
    def hostname(self) -> str:
        self.set_config_param(
            key=self.KEYS[self.HOSTNAME],
            value=str(self._hostname)
        )
        return str(self._hostname)

    @hostname.setter
    def hostname(self, value: str | Hostname) -> None:
        if isinstance(value, str):
            self._hostname = Hostname(value)
        elif isinstance(value, Hostname):
            self._hostname = value
        else:
            if not (isinstance(value, str) or isinstance(value, Hostname)):
                raise TypeError(
                    f'Hostname of {value} is invalid, must be of type "str" or "Hostname"'
                )

    # IP Address:
    # - the IP address at which the computer can be accessed
    @property
    def ip_address(self) -> IP:
        self.set_config_param(
            key=self.KEYS[self.IP_ADDRESS],
            value=self._ip
        )
        return self._ip

    @ip_address.setter
    def ip_address(self, value: str | IP) -> None:
        if isinstance(value, str):
            self._ip = IP(value)
        elif isinstance(value, IP):
            self._ip = value
        else:
            if not (isinstance(value, dict) or isinstance(value, IP)):
                raise TypeError(
                    f'IP address of {value} is invalid, must be of type "str" or "IP"'
                )


# HostListConfig
# - list of hosts that are involved with the system
class HostListConfig(ListConfig[HostConfig, str]):

    DEFAULTS = [HostConfig.DEFAULTS]

    def __init__(self) -> None:
        super().__init__(
            uid=lambda obj: obj.hostname,
            obj_type=HostConfig,
            uid_type=str
        )

    def to_dict(self) -> List[dict]:
        hosts = []
        for host in self.get_all():
            hosts.append(host.config)
        return hosts
