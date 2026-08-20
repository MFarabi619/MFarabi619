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


import re


class Namespace:
    def __init__(
            self,
            name: str = '/'
            ) -> None:
        self.assert_valid(name)
        self.name = name

    def __eq__(self, other: object) -> bool:
        if isinstance(other, str):
            return self.name == other
        elif isinstance(other, Namespace):
            return self.name == other.name
        else:
            return False

    def __str__(self) -> str:
        return str(self.name)

    @staticmethod
    def is_valid(name: str) -> bool:
        # Must not be Empty
        if name == '':
            return False
        # Must Contain:
        #  - [0-9|a-z|A-Z]
        #  - Underscores (_)
        #  - Forward Slashed (/)
        allowed = re.compile('[a-z|0-9|_|/|~]', re.IGNORECASE)
        if not all(allowed.match(c) for c in name):
            return False
        # May start with (~) but be followed by (/)
        if name[0] == '~':
            if name[1] != '/':
                return False
        # Must not Start with Digit [0-9], May Start with (~)
        if str(name[0]).isdigit():
            return False
        # Must not End with Forward Slash (/)
        if name[-1] == '/':
            return False
        # Must not contain any number of repeated forward slashed (/)
        if '//' in name:
            return False
        # Must not contain any number of repeated underscores (_)
        if '__' in name:
            return False
        return True

    @staticmethod
    def assert_valid(name: str) -> None:
        # Empty
        if not name:
            raise ValueError('Namespace cannot be empty')
        # Allowed characters
        allowed = re.compile('[a-z|0-9|_|/|~]', re.IGNORECASE)
        if not all(allowed.match(c) for c in name):
            raise ValueError(f"""Namespace "{name}" can only contain:
 - [A-Z|a-z|0-9],
 - underscores (_),
 - forward slahes (/),
 - leading tilde (~)""")
        # Leading Tilde (~)
        if name[0] == '~':
            if name[1] != '/':
                raise ValueError('Namespace starting with "~" must be followed by "/"')
        # Leading Digit
        if str(name[0]).isdigit():
            raise ValueError(f'Namespace "{name}" may not start with a digit')
        # Ending Forward Slash (/)
        if len(name) != 1 and name[-1] == '/':
            raise ValueError(f'Namespace "{name}" may not end with a forward slash (/)')
        # Repeated Forward Slash (/)
        if '//' in name:
            raise ValueError(f'Namespace "{name}" may not contain repeated forward slashes (/)')
        # Repeated Underscores (/)
        if '__' in name:
            raise ValueError(f'Namespace "{name}" may not contain repeated underscores (_)')

    @staticmethod
    def clean(name: str) -> str:
        # Swap dashes to underscores
        clean = name.replace('-', '_')
        # Remove repeated forward slashes
        while '//' in clean:
            clean = clean.replace('//', '/')
        # Remove repeated underscores
        while '__' in clean:
            clean = clean.replace('__', '_')
        return clean
