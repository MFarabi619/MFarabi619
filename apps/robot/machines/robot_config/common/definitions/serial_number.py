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


from typing import NamedTuple


class SerialNumber(NamedTuple):
    model: str
    unit: str

    def __str__(self) -> str:
        return self.get_serial()

    @classmethod
    def parse(cls, serial: str) -> 'SerialNumber':
        if not isinstance(serial, str):
            raise TypeError(f'Serial Number "{serial}" must be string')
        model, _, unit = serial.lower().strip().partition('-')
        if model == 'generic':
            return cls(model, unit or 'xxxx')
        if not model or not unit.isdecimal():
            raise ValueError(f'Serial number unit entry in "{serial}" must be an integer')
        return cls(model, unit)

    def get_model(self) -> str:
        return self.model

    def get_unit(self) -> str:
        return self.unit

    def get_serial(self) -> str:
        return f'{self.model}-{self.unit}'
