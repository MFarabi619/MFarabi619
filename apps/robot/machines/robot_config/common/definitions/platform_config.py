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


# Platform
# - all supported platforms
class Platform:
    # MD30C drivetrain
    ROBOT = 'robot'
    # Freenove
    FREENOVE = 'freenove'
    # Generic Robot
    GENERIC = 'generic'

    ALL = [
        ROBOT,
        FREENOVE,
        GENERIC,
    ]

    @staticmethod
    def assert_is_supported(platform):
        """
        Raise an exception if the platform is not presently supported/usable.

        Unsupported platforms may become supported in a future release, and there are no plans
        to remove it; it simply is not (yet) compatible with the current ROS release.

        @param platform  The platform-identifying serial number prefix (e.g. 'robot', 'freenove')

        @exception UnsupportedPlatformException if the platform is not supported
        """
        # currently all platforms are supported, nothing to do
        pass

    @staticmethod
    def notify_if_deprecated(platform):
        """
        Print a notification that the selected platform is deprecated.

        Deprecated platforms may have their support removed in a future version

        @param platform  The platform-identifying serial number prefix (e.g. 'robot', 'freenove')
        """
        # currently nothing is deprecated, so nothing to do here (yet)
        pass
