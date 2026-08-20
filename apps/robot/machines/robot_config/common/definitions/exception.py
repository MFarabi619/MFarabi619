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


class UnsupportedAccessoryException(AssertionError):
    """
    Indicates that an accessory is not supported in the current release.

    The accessory may become available in the future.
    """

    def __init__(self, message):
        """
        Create a new exception.

        @param message  A message indicating why this accessory is not supported
        """
        super().__init__(message)


class UnsupportedPlatformException(AssertionError):
    """
    Indicates that a platform is not supported in the current release.

    The platform may become available in the future.
    """

    def __init__(self, message):
        """
        Create a new exception.

        @param message  A message indicating why this platform is not supported
        """
        super().__init__(message)
