from robot_config.common.types.platform import Platform


# SerialNumber
# - our robot's serial number
# - ex. rover-0000
class SerialNumber:
    SERIAL_NUMBER = 'serial_number'

    def __init__(self, sn: str) -> None:
        self.model, self.unit = SerialNumber.parse(sn)

    def __str__(self) -> str:
        return self.get_serial()

    def from_dict(self, config: dict) -> None:
        if not isinstance(config, dict):
            raise TypeError('Config must be of type "dict"')
        if self.SERIAL_NUMBER not in config:
            raise ValueError(f'Key "{self.SERIAL_NUMBER}" must be in config')
        self.model, self.unit = SerialNumber.parse(config[self.SERIAL_NUMBER])

    @staticmethod
    def parse(sn: str) -> tuple:
        if not isinstance(sn, str):
            raise TypeError(f'Serial Number "{sn}" must be string')
        sn_tokens = sn.lower().strip().split('-')
        if len(sn_tokens) <= 0 or len(sn_tokens) >= 4:
            raise ValueError(
                f'Serial number {sn}" must be delimited by hypens "-" and have 2 or 3 fields (e.g. cpr-rover-00001 or rover-00001), or 1 (generic) field'  # noqa: E501
            )
        # Remove CPR Prefix
        if len(sn_tokens) == 3:
            if sn_tokens[0] != 'cpr':
                raise ValueError(
                    f'Serial number with 3 fields must start with "cpr" not "{sn_tokens[0]}"'
                )
            sn_tokens = sn_tokens[1:]
        # Match to Robot
        if sn_tokens[0] not in Platform.ALL:
            raise ValueError(
                f'Serial number model entry {sn_tokens[0]} must be one of {Platform.ALL}'
            )

        # Verify that the platform is well-supported and not deprecated
        Platform.assert_is_supported(sn_tokens[0])
        Platform.notify_if_deprecated(sn_tokens[0])

        # Generic Robot
        if sn_tokens[0] == Platform.GENERIC:
            if len(sn) > 1:
                return (sn_tokens[0], sn[1])
            else:
                return (sn_tokens[0], 'xxxx')
        # Check Number
        if not sn_tokens[1].isdecimal():
            raise ValueError(f'Serial number unit entry "{sn_tokens[1]}" must be an integer')
        return (sn_tokens[0], sn_tokens[1])

    def get_model(self) -> str:
        return self.model

    def get_unit(self) -> str:
        return self.unit

    def get_serial(self, prefix=False) -> str:
        if prefix:
            return '-'.join(['cpr', self.model, self.unit])
        else:
            return '-'.join([self.model, self.unit])
