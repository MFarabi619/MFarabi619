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

from robot_config.common.definitions.exception import UnsupportedAccessoryException


class Accessory():
    # Defaults
    PARENT = 'default_mount'
    XYZ = [0.0, 0.0, 0.0]
    RPY = [0.0, 0.0, 0.0]

    def __init__(
            self,
            name: str,
            parent: str = PARENT,
            xyz: List[float] = XYZ,
            rpy: List[float] = RPY
            ) -> None:

        self.assert_is_supported()
        if self.is_deprecated:
            print(f'{type(self)} is deprecated')

        self.name = ''
        self.parent = ''
        self.xyz: List[float] = []
        self.rpy: List[float] = []
        self.set_name(name)
        self.set_parent(parent)
        self.set_xyz(xyz)
        self.set_rpy(rpy)

    def to_dict(self) -> dict:
        return {
            'name': self.get_name(),
            'parent': self.get_parent(),
            'xyz': self.get_xyz(),
            'rpy': self.get_rpy(),
        }

    def from_dict(self, d: dict) -> None:
        if 'name' in d:
            self.set_name(d['name'])
        if 'parent' in d:
            self.set_parent(d['parent'])
        if 'xyz' in d:
            self.set_xyz(d['xyz'])
        if 'rpy' in d:
            self.set_rpy(d['rpy'])

    def get_name(self) -> str:
        return self.name

    def set_name(self, name: str) -> None:
        self.assert_valid_link(name)
        self.name = name

    def get_parent(self) -> str:
        return self.parent

    def set_parent(self, parent: str) -> None:
        self.assert_valid_link(parent)
        self.parent = parent

    def get_xyz(self) -> List[float]:
        return self.xyz

    def set_xyz(self, xyz: List[float]) -> None:
        self.assert_valid_triplet(
            xyz,
            'XYZ must be a list of exactly three float values'
        )
        self.xyz = xyz

    def get_rpy(self) -> List[float]:
        return self.rpy

    def set_rpy(self, rpy: List[float]) -> None:
        self.assert_valid_triplet(
            rpy,
            'RPY must be a list of exactly three float values'
        )
        self.rpy = rpy

    @staticmethod
    def assert_valid_link(link: str) -> None:
        # Link name must be a string
        if not isinstance(link, str):
            raise TypeError(f'Link name "{link}" must be string')
        # Link name must not be empty
        if not link:
            raise ValueError(f'Link name "{link}" must not be empty')
        # Link name must not have spaces
        if ' ' in link:
            raise ValueError(f'Link name "{link}" must no have spaces')
        # Link name must not start with a digit
        if link[0].isdigit():
            raise ValueError(f'Link name "{link} must not start with a digit')

    @staticmethod
    def assert_valid_triplet(tri: List[float], msg: str | None = None) -> None:
        if msg is None:
            msg = 'Triplet must be a list of three float values'
        # Triplet must be a list
        if not isinstance(tri, list):
            raise TypeError(msg)
        # Triplet must have a length of 3
        if len(tri) != 3:
            raise ValueError(msg)
        # Triplet must be all floats
        for i in tri:
            if not isinstance(i, float):
                raise TypeError(msg)

    @staticmethod
    def assert_is_supported():
        """
        Override this method to temporarily disable accessories that are not currently supported.

        When disabling an accessory, raise a
        robot_config.common.definitions.exception.UnsupportedAccessoryException
        with a suitable mesage (e.g. 'SpamEggs driver is not yet released for ROS 2 Jazzy')

        @return None

        @exception  UnsupportedAccessoryException if the accessory is not
                    supported
        """
        pass

    @property
    def is_suppported(self):
        try:
            self.assert_is_supported()
            return True
        except UnsupportedAccessoryException:
            return False

    @property
    def is_deprecated(self):
        """
        Override this method to indicate that this accessory has been deprecated.

        Deprecated accessories may be removed completely in the future.  See:
        - is_supported
        - assert_is_supported

        When flagging an accessory for deprecation, simply override it to return True
        """
        return False


class IndexedAccessory(Accessory):

    def __init__(
            self,
            idx: int | None = None,
            name: str | None = None,
            parent: str = Accessory.PARENT,
            xyz: List[float] = Accessory.XYZ,
            rpy: List[float] = Accessory.RPY
            ) -> None:
        if name is None:
            name = self.get_name_from_idx(0)
        super().__init__(
            name,
            parent,
            xyz,
            rpy
        )
        # Index:
        # - index of sensor
        # - used to modify parameters to allow for multiple instances
        #   of the same sensor.
        self.idx = 0
        if idx is not None:
            self.set_idx(idx)

    @classmethod
    def get_name_from_idx(cls, idx: int) -> str:
        return 'accessory_%s' % idx

    def get_idx(self) -> int:
        return self.idx

    def set_idx(self, idx: int) -> None:
        if not isinstance(idx, int):
            raise TypeError(f'Index {idx} must be an integer')
        if idx < 0:
            raise ValueError(f'Index {idx} must be a positive integer')
        self.name = self.get_name_from_idx(idx)
