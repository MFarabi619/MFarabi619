import re


# Hostname
# - hostname class
class Hostname:

    def __init__(self, hostname: str = 'hostname') -> None:
        self.assert_valid(hostname)
        self.hostname = hostname

    def __eq__(self, other: object) -> bool:
        if isinstance(other, str):
            return self.hostname == other
        elif isinstance(other, Hostname):
            return self.hostname == other.hostname
        return False

    def __str__(self) -> str:
        return self.hostname

    @staticmethod
    def is_valid(hostname: str) -> bool:
        # Max 253 ASCII Characters
        if len(hostname) > 253:
            return False
        # No Trailing Dots
        # - not exactly a standard, but generally results in undefined
        #       behaviour and should be avoided
        if hostname[-1] == '.':
            return False
        # Only [A-Z][0-9] and '-' Allowed
        # - cannot end or start with a hyphen ('-')
        allowed = re.compile(r'(?!-)[A-Z\d-]{1,63}(?<!-)$', re.IGNORECASE)
        return all(allowed.match(x) for x in hostname.split('.'))

    @staticmethod
    def assert_valid(hostname: str):
        if not isinstance(hostname, str):
            raise TypeError(f'Hostname {hostname} most be of type "str"')
        # Min 1 ASCII Characters
        if len(hostname) == 0:
            raise ValueError('Hostname cannot be blank')
        # Max 253 ASCII Characters
        if len(hostname) >= 254:
            raise ValueError(f'Hostname "{hostname}" exceeds 253 ASCII character limit.')
        # No Trailing Dots
        if hostname.endswith('.'):
            raise ValueError(f'Hostname "{hostname}" cannot end with a "." (period).')
        # Only [A-Z][0-9] and '-' Allowed
        allowed = re.compile(r'(?!-)[A-Z\d-]{1,63}(?<!-)$', re.IGNORECASE)
        if not all(allowed.match(x) for x in hostname.split('.')):
            raise ValueError(
                f'Hostname {hostname} cannot contain characters other than [A-Z][a-z][0-9] and -'
            )
