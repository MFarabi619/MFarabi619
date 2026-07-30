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


from robot_config.common.definitions.platform_config import Platform


# SerialNumber
# - our robot's serial number
# - ex. robot-0000
class SerialNumber:
    SERIAL_NUMBER = 'serial_number'

    def __init__(self, sn: str) -> None:
        self.model, self.unit = SerialNumber.parse(sn)

    def __str__(self) -> str:
        return self.get_serial()

    def from_dict(self, config: dict) -> None:
        if not isinstance(config, dict):
            raise TypeError('Config must be of type "dict"')
        if self.SERIAL_NUMBER not in config:
            raise ValueError(f'Key "{self.SERIAL_NUMBER}" must be in config')
        self.model, self.unit = SerialNumber.parse(config[self.SERIAL_NUMBER])

    @staticmethod
    def parse(sn: str) -> tuple:
        if not isinstance(sn, str):
            raise TypeError(f'Serial Number "{sn}" must be string')
        sn_tokens = sn.lower().strip().split('-')
        if len(sn_tokens) <= 0 or len(sn_tokens) >= 3:
            raise ValueError(
                f'Serial number "{sn}" must be delimited by hyphens "-" and have 2 fields (e.g. robot-00001), or 1 (generic) field'  # noqa: E501
            )
        # Match to Robot
        if sn_tokens[0] not in Platform.ALL:
            raise ValueError(
                f'Serial number model entry {sn_tokens[0]} must be one of {Platform.ALL}'
            )

        # Verify that the platform is well-supported and not deprecated
        Platform.assert_is_supported(sn_tokens[0])
        Platform.notify_if_deprecated(sn_tokens[0])

        # Generic Robot
        if sn_tokens[0] == Platform.GENERIC:
            if len(sn_tokens) > 1:
                return (sn_tokens[0], sn_tokens[1])
            else:
                return (sn_tokens[0], 'xxxx')
        # Check Number
        if not sn_tokens[1].isdecimal():
            raise ValueError(f'Serial number unit entry "{sn_tokens[1]}" must be an integer')
        return (sn_tokens[0], sn_tokens[1])

    def get_model(self) -> str:
        return self.model

    def get_unit(self) -> str:
        return self.unit

    def get_serial(self) -> str:
        return '-'.join([self.model, self.unit])
