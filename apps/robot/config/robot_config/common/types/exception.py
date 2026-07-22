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
