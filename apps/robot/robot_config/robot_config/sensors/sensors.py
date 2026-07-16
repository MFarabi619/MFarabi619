from typing import List

from robot_config.common.types.config import BaseConfig
from robot_config.common.types.list import OrderedListConfig
from robot_config.common.utils.dictionary import flip_dict
from robot_config.sensors.types.camera import (
    BaseCamera,
    IMX296GS,
    OrbbecGemini335L,
    USBWebcam,
)
from robot_config.sensors.types.gps import BaseGPS, Gpsd
from robot_config.sensors.types.sensor import BaseSensor


class Camera():
    IMX296_GS = IMX296GS.SENSOR_MODEL
    USB_WEBCAM = USBWebcam.SENSOR_MODEL
    ORBBEC_GEMINI_335L = OrbbecGemini335L.SENSOR_MODEL

    MODEL = {
        IMX296_GS: IMX296GS,
        USB_WEBCAM: USBWebcam,
        ORBBEC_GEMINI_335L: OrbbecGemini335L,
    }

    @classmethod
    def assert_model(cls, model: str) -> None:
        if model not in cls.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{cls.MODEL.keys()}"')

    def __new__(cls, model: str) -> BaseCamera:
        cls.assert_model(model)
        return cls.MODEL[model]()


class GlobalPositioningSystem():
    GPSD = Gpsd.SENSOR_MODEL

    MODEL = {
        GPSD: Gpsd,
    }

    @classmethod
    def assert_model(cls, model: str) -> None:
        if model not in cls.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{cls.MODEL.keys()}"')

    def __new__(cls, model: str) -> BaseGPS:
        cls.assert_model(model)
        return cls.MODEL[model]()


class SensorListConfig(OrderedListConfig[BaseSensor]):

    def __init__(self) -> None:
        super().__init__(obj_type=BaseSensor)

    def to_dict(self) -> List[dict]:
        d = []
        for accessory in self.get_all():
            d.append(accessory.to_dict())
        return d


class SensorConfig(BaseConfig):

    SENSORS = 'sensors'
    CAMERA = BaseCamera.SENSOR_TYPE
    GPS = BaseGPS.SENSOR_TYPE

    TEMPLATE = {
        SENSORS: {
            CAMERA: CAMERA,
            GPS: GPS,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS = {
        CAMERA: [],
        GPS: [],
    }

    def __init__(
            self,
            config: dict = {},
            camera: List[BaseCamera] = DEFAULTS[CAMERA],
            gps: List[BaseGPS] = DEFAULTS[GPS],
            ) -> None:
        # List Initialization
        self._camera = SensorListConfig()
        self._gps = SensorListConfig()
        # Initialization
        self.camera = camera
        self.gps = gps
        # Template
        template = {
            self.KEYS[self.CAMERA]: SensorConfig.camera,
            self.KEYS[self.GPS]: SensorConfig.gps,
        }
        super().__init__(template, config, self.SENSORS)

    @property
    def camera(self) -> OrderedListConfig:
        self.set_config_param(
            key=self.KEYS[self.CAMERA],
            value=self._camera.to_dict()
        )
        return self._camera

    @camera.setter
    def camera(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'Camera must be list of "dict". Got {value}')
        for d in value:
            if not isinstance(d, dict):
                raise TypeError(f'Camera {d} must be of type "dict"')
            if 'model' not in d:
                raise ValueError(f'Camera {d} does not have a "model" parameter')
        sensor_list = []
        for d in value:
            sensor = Camera(d['model'])
            sensor.from_dict(d)
            sensor_list.append(sensor)
        self._camera.set_all(sensor_list)

    @property
    def gps(self) -> OrderedListConfig:
        self.set_config_param(
            key=self.KEYS[self.GPS],
            value=self._gps.to_dict()
        )
        return self._gps

    @gps.setter
    def gps(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'GPS must be list of "dict". Got {value}')
        for d in value:
            if not isinstance(d, dict):
                raise TypeError(f'GPS {d} must be of type "dict"')
            if 'model' not in d:
                raise ValueError(f'GPS {d} does not have a "model" parameter')
        sensor_list = []
        for d in value:
            sensor = GlobalPositioningSystem(d['model'])
            sensor.from_dict(d)
            sensor_list.append(sensor)
        self._gps.set_all(sensor_list)

    # Get All Sensors
    def get_all_sensors(self) -> List[BaseSensor]:
        sensors = []
        sensors.extend(self.get_all_cameras())
        sensors.extend(self.get_all_gps())
        return sensors

    # Camera: Get All
    def get_all_cameras(self) -> List[BaseCamera]:
        return self._camera.get_all()

    # GPS: Get All
    def get_all_gps(self) -> List[BaseGPS]:
        return self._gps.get_all()
