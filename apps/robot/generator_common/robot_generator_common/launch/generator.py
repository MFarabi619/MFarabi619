#!/usr/bin/env python3

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


import os

from robot_generator_common.common import BaseGenerator


class LaunchGenerator(BaseGenerator):
    def __init__(self, setup_path: str, output_path: str) -> None:
        super().__init__(setup_path)
        self.output_path = output_path
        os.makedirs(self.output_path, exist_ok=True)

    def generate(self) -> None:
        raise NotImplementedError()
