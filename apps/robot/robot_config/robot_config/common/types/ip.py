# IP
# - ip class
class IP:

    def __init__(self, ip: str = '0.0.0.0') -> None:
        self.assert_valid(ip)
        self.ip_str = ip

    def __eq__(self, other: object) -> bool:
        if isinstance(other, str):
            return self.ip_str == other
        elif isinstance(other, IP):
            return self.ip_str == other.ip_str
        else:
            return False

    def __str__(self) -> str:
        return self.ip_str

    @staticmethod
    def is_valid(ip: str) -> bool:
        # Must be String
        if not isinstance(ip, str):
            return False
        # Must have Four Fields Delimited by '.'
        fields = ip.split('.')
        if not len(fields) == 4:
            return False
        # All Fields must be Integers and 8 Bit Wide
        for field in fields:
            if not field.isdecimal():
                return False
            field_int = int(field)
            if not (0 <= field_int < 256):
                return False
        return True

    @staticmethod
    def assert_valid(ip: str) -> None:
        # Must be String
        if not isinstance(ip, str):
            raise TypeError(f'IP "{ip}" must be of type "str"')
        # Must have Four Fields Delimited by '.'
        fields = ip.split('.')
        if len(fields) != 4:
            raise ValueError(f'IP "{ip}" must have 4 fields')
        for field in fields:
            # Fields Must be Integer
            if not field.isdecimal():
                raise ValueError(f'IP "{ip}" fields must be integers')
            # Fields Must be 8-Bits Wide
            field_int = int(field)
            if field_int < 0 or field_int > 255:
                raise ValueError(f'IP {ip} fields must be in range 0 to 255')
