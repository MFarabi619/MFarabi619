# Platform
# - all supported platforms
class Platform:
    # MD30C rover
    ROVER = 'rover'
    # Freenove
    FREENOVE = 'freenove'
    # Generic Robot
    GENERIC = 'generic'

    ALL = [
        ROVER,
        FREENOVE,
        GENERIC,
    ]

    @staticmethod
    def assert_is_supported(platform):
        """
        Raise an exception if the platform is not presently supported/usable.

        Unsupported platforms may become supported in a future release, and there are no plans
        to remove it; it simply is not (yet) compatible with the current ROS release.

        @param platform  The platform-identifying serial number prefix (e.g. 'rover', 'freenove')

        @exception UnsupportedPlatformException if the platform is not supported
        """
        # currently all platforms are supported, nothing to do
        pass

    @staticmethod
    def notify_if_deprecated(platform):
        """
        Print a notification that the selected platform is deprecated.

        Deprecated platforms may have their support removed in a future version

        @param platform  The platform-identifying serial number prefix (e.g. 'rover', 'freenove')
        """
        # currently nothing is deprecated, so nothing to do here (yet)
        pass
