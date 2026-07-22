from typing import List

from robot_config.common.types.config import BaseConfig
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

    DEFAULTS = {
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
