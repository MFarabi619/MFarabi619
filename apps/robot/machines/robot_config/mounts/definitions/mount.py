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

from robot_config.common.definitions.accessory import Accessory, IndexedAccessory


class BaseMount(IndexedAccessory):
    MOUNT_MODEL = 'base_mount'

    def __init__(
        self,
        idx: int | None = None,
        name: str | None = None,
        parent: str = Accessory.PARENT,
        xyz: List[float] = Accessory.XYZ,
        rpy: List[float] = Accessory.RPY,
    ) -> None:
        super().__init__(idx, name, parent, xyz, rpy)

    def to_dict(self) -> dict:
        d: dict = {}
        d['parent'] = self.get_parent()
        d['xyz'] = self.get_xyz()
        d['rpy'] = self.get_rpy()
        return d

    def from_dict(self, d: dict) -> None:
        if 'parent' in d:
            self.set_parent(d['parent'])
        if 'xyz' in d:
            self.set_xyz(d['xyz'])
        if 'rpy' in d:
            self.set_rpy(d['rpy'])

    @classmethod
    def get_mount_model(cls) -> str:
        return cls.MOUNT_MODEL

    @classmethod
    def get_name_from_idx(cls, idx: int) -> str:
        return '%s_%s' % (
            cls.get_mount_model(),
            idx
        )


class CameraMount(BaseMount):
    MOUNT_MODEL = 'camera_mount'
