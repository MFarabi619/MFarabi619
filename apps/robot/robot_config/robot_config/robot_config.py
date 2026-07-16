from robot_config.common.types.config import BaseConfig
from robot_config.common.utils.yaml import read_yaml, write_yaml
from robot_config.mounts.mounts import MountsConfig
from robot_config.platform.platform import PlatformConfig
from robot_config.sensors.sensors import SensorConfig
from robot_config.system.system import SystemConfig


# RobotConfig:
#  - top level configurator
class RobotConfig(BaseConfig):

    VERSION = 'version'
    SERIAL_NUMBER = 'serial_number'
    SYSTEM = 'system'
    PLATFORM = 'platform'
    SENSORS = 'sensors'
    MOUNTS = 'mounts'

    TEMPLATE = {
        SERIAL_NUMBER: SERIAL_NUMBER,
        VERSION: VERSION,
        SYSTEM: SYSTEM,
        PLATFORM: PLATFORM,
        SENSORS: SENSORS,
        MOUNTS: MOUNTS,
    }

    KEYS = TEMPLATE

    DEFAULTS = {
        SERIAL_NUMBER: 'generic',
        VERSION: 0,
        SYSTEM: SystemConfig.DEFAULTS,
        PLATFORM: PlatformConfig.DEFAULTS,
        SENSORS: SensorConfig.DEFAULTS,
        MOUNTS: MountsConfig.DEFAULTS,
    }

    def __init__(self, config: dict | str = None) -> None:
        # Read YAML
        if isinstance(config, str):
            config = self.read(config)
        # Reset the global serial number variable
        BaseConfig.set_serial_number('generic')
        # Initialization of Sub-Configs
        self._config = {}
        self._system = SystemConfig(self.DEFAULTS[self.SYSTEM])
        self._platform = PlatformConfig(self.DEFAULTS[self.PLATFORM])
        self._sensors = SensorConfig(self.DEFAULTS[self.SENSORS])
        self._mounts = MountsConfig(self.DEFAULTS[self.MOUNTS])
        # Initialization
        self.serial_number = self.DEFAULTS[self.SERIAL_NUMBER]
        self.version = self.DEFAULTS[self.VERSION]
        # Setter Template
        setters = {
            self.SERIAL_NUMBER: RobotConfig.serial_number,
            self.VERSION: RobotConfig.version,
            self.SYSTEM: RobotConfig.system,
            self.PLATFORM: RobotConfig.platform,
            self.SENSORS: RobotConfig.sensors,
            self.MOUNTS: RobotConfig.mounts,
        }
        # Set from Config
        super().__init__(setters, config)

    def read(self, file: str | dict) -> None:
        self._file = None
        if isinstance(file, dict):
            return file
        self._file = file
        return read_yaml(file)

    def write(self, file: str) -> None:
        write_yaml(file, self.config)

    @property
    def serial_number(self) -> str:
        self.set_config_param(
            self.SERIAL_NUMBER,
            str(self.get_serial_number())
        )
        return self.get_serial_number()

    @serial_number.setter
    def serial_number(self, sn: str) -> None:
        self.set_serial_number(sn)
        self._system.update(serial_number=True)
        self._platform.update(serial_number=True)
        self._sensors.update(serial_number=True)
        self._mounts.update(serial_number=True)

    @property
    def version(self) -> int:
        self.set_config_param(self.VERSION, self._version)
        return self._version

    @version.setter
    def version(self, v: int) -> None:
        if not isinstance(v, int):
            raise ValueError(f'Version {v} must be of type "int" not "{type(v)}"')
        self._version = v

    @property
    def system(self) -> SystemConfig:
        self.set_config_param(
            self.SYSTEM,
            self._system.config[self.SYSTEM])
        return self._system

    @system.setter
    def system(self, config: dict) -> None:
        self._system.config = config

    @property
    def platform(self) -> PlatformConfig:
        self.set_config_param(
            self.PLATFORM,
            self._platform.config[self.PLATFORM])
        return self._platform

    @platform.setter
    def platform(self, config: dict) -> None:
        self._platform.config = config

    @property
    def sensors(self) -> SensorConfig:
        self.set_config_param(
            self.SENSORS,
            self._sensors.config[self.SENSORS])
        return self._sensors

    @sensors.setter
    def sensors(self, config: dict) -> None:
        self._sensors.config = config

    @property
    def mounts(self) -> MountsConfig:
        self.set_config_param(
            self.MOUNTS,
            self._mounts.config[self.MOUNTS])
        return self._mounts

    @mounts.setter
    def mounts(self, config: dict) -> None:
        self._mounts.config = config
