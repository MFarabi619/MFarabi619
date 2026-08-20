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
from robot_config.common.definitions.list import OrderedListConfig
from robot_config.common.utils.dictionary import flip_dict
from robot_config.mounts.definitions.mount import BaseMount, CameraMount


class Mount():
    CAMERA_MOUNT = CameraMount.MOUNT_MODEL

    MODEL = {
        CAMERA_MOUNT: CameraMount,
    }

    def __new__(cls, model: str) -> BaseMount:  # type: ignore[misc]
        if model not in Mount.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{Mount.MODEL.keys()}"')
        return Mount.MODEL[model]()


class MountListConfig(OrderedListConfig[BaseMount]):

    def __init__(self) -> None:
        super().__init__(obj_type=BaseMount)

    def to_dict(self) -> List[dict]:
        d = []
        for accessory in self.get_all():
            d.append(accessory.to_dict())
        return d


class MountsConfig(BaseConfig):

    MOUNTS = 'mounts'
    CAMERA_MOUNT = CameraMount.MOUNT_MODEL

    TEMPLATE = {
        MOUNTS: {
            CAMERA_MOUNT: CAMERA_MOUNT,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS: dict = {
        CAMERA_MOUNT: [],
    }

    def __init__(
            self,
            config: dict = {},
            camera_mount: List[dict] = DEFAULTS[CAMERA_MOUNT],
            ) -> None:
        # Initialization
        self.camera_mount = camera_mount
        # Template
        template = {
            self.KEYS[self.CAMERA_MOUNT]: MountsConfig.camera_mount,
        }
        super().__init__(template, config, self.MOUNTS)

    @property
    def camera_mount(self) -> OrderedListConfig:
        self.set_config_param(
            key=self.KEYS[self.CAMERA_MOUNT],
            value=self._camera_mount.to_dict()
        )
        return self._camera_mount

    @camera_mount.setter
    def camera_mount(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'Camera mounts must be list of "dict". Got {value}')
        for i in value:
            if not isinstance(i, dict):
                raise TypeError(f'Camera mount {i} must be of type "dict"')
        mounts = MountListConfig()
        mount_list: List[BaseMount] = []
        for d in value:
            mount = CameraMount()
            mount.from_dict(d)
            mount_list.append(mount)
        mounts.set_all(mount_list)
        self._camera_mount = mounts

    # Get All Mounts
    def get_all_mounts(self) -> List[BaseMount]:
        mounts = []
        mounts.extend(self.camera_mount.get_all())
        return mounts
