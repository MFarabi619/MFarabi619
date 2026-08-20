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
from robot_config.common.utils.dictionary import flip_dict


class PlatformConfig(BaseConfig):

    PLATFORM = 'platform'

    ATTACHMENTS = 'attachments'

    TEMPLATE = {
        PLATFORM: {
            ATTACHMENTS: ATTACHMENTS,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS: dict = {
        ATTACHMENTS: [],
    }

    def __init__(
            self,
            config: dict = {},
            attachments: list = DEFAULTS[ATTACHMENTS],
            ) -> None:
        # Initialization
        self._config = {}
        self.attachments = attachments
        # Setter Template
        setters = {
            self.KEYS[self.ATTACHMENTS]: PlatformConfig.attachments,
        }
        super().__init__(setters, config, self.PLATFORM)

    @property
    def attachments(self) -> list:
        self.set_config_param(
            key=self.KEYS[self.ATTACHMENTS],
            value=self._attachments
        )
        return self._attachments

    @attachments.setter
    def attachments(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'Attachments must be of type "list". Got {value}')
        for d in value:
            if not isinstance(d, dict):
                raise TypeError(f'Attachment {d} must be of type "dict"')
        self._attachments = value
