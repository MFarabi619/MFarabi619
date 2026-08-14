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


from typing import cast, List

from robot_config.common.definitions.config import BaseConfig
from robot_config.common.definitions.list import OrderedListConfig
from robot_config.common.utils.dictionary import flip_dict
from robot_config.sensors.definitions.camera import (
    BaseCamera,
    IMX296GS,
    OakDProWPoe,
    OakDSR,
    OrbbecGemini335L,
    USBWebcam,
)
from robot_config.sensors.definitions.gps import AdafruitUltimateGpsHat, BaseGPS
from robot_config.sensors.definitions.imu import BaseIMU, Bno085
from robot_config.sensors.definitions.sensor import BaseSensor


class Camera():
    IMX296_GS = IMX296GS.SENSOR_MODEL
    USB_WEBCAM = USBWebcam.SENSOR_MODEL
    OAK_D_SR = OakDSR.SENSOR_MODEL
    OAK_D_PRO_W_POE = OakDProWPoe.SENSOR_MODEL
    ORBBEC_GEMINI_335L = OrbbecGemini335L.SENSOR_MODEL

    MODEL = {
        IMX296_GS: IMX296GS,
        USB_WEBCAM: USBWebcam,
        OAK_D_SR: OakDSR,
        OAK_D_PRO_W_POE: OakDProWPoe,
        ORBBEC_GEMINI_335L: OrbbecGemini335L,
    }

    @classmethod
    def assert_model(cls, model: str) -> None:
        if model not in cls.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{cls.MODEL.keys()}"')

    def __new__(cls, model: str) -> BaseCamera:  # type: ignore[misc]
        cls.assert_model(model)
        return cls.MODEL[model]()


class GlobalPositioningSystem():
    ADAFRUIT_ULTIMATE_GPS_HAT = AdafruitUltimateGpsHat.SENSOR_MODEL

    MODEL = {
        ADAFRUIT_ULTIMATE_GPS_HAT: AdafruitUltimateGpsHat,
    }

    @classmethod
    def assert_model(cls, model: str) -> None:
        if model not in cls.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{cls.MODEL.keys()}"')

    def __new__(cls, model: str) -> BaseGPS:  # type: ignore[misc]
        cls.assert_model(model)
        return cls.MODEL[model]()


class InertialMeasurementUnit():
    BNO085 = Bno085.SENSOR_MODEL

    MODEL = {
        BNO085: Bno085,
    }

    @classmethod
    def assert_model(cls, model: str) -> None:
        if model not in cls.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{cls.MODEL.keys()}"')

    def __new__(cls, model: str) -> BaseIMU:  # type: ignore[misc]
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
    IMU = BaseIMU.SENSOR_TYPE

    TEMPLATE = {
        SENSORS: {
            CAMERA: CAMERA,
            GPS: GPS,
            IMU: IMU,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS: dict = {
        CAMERA: [],
        GPS: [],
        IMU: [],
    }

    def __init__(
            self,
            config: dict = {},
            camera: List[dict] = DEFAULTS[CAMERA],
            gps: List[dict] = DEFAULTS[GPS],
            imu: List[dict] = DEFAULTS[IMU],
            ) -> None:
        # List Initialization
        self._camera = SensorListConfig()
        self._gps = SensorListConfig()
        self._imu = SensorListConfig()
        # Initialization
        self.camera = camera
        self.gps = gps
        self.imu = imu
        # Template
        template = {
            self.KEYS[self.CAMERA]: SensorConfig.camera,
            self.KEYS[self.GPS]: SensorConfig.gps,
            self.KEYS[self.IMU]: SensorConfig.imu,
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
        sensor_list: List[BaseSensor] = []
        for d in value:
            sensor = cast(BaseCamera, Camera(d['model']))
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
        sensor_list: List[BaseSensor] = []
        for d in value:
            sensor = cast(BaseGPS, GlobalPositioningSystem(d['model']))
            sensor.from_dict(d)
            sensor_list.append(sensor)
        self._gps.set_all(sensor_list)

    @property
    def imu(self) -> OrderedListConfig:
        self.set_config_param(
            key=self.KEYS[self.IMU],
            value=self._imu.to_dict()
        )
        return self._imu

    @imu.setter
    def imu(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'IMU must be list of "dict". Got {value}')
        for d in value:
            if not isinstance(d, dict):
                raise TypeError(f'IMU {d} must be of type "dict"')
            if 'model' not in d:
                raise ValueError(f'IMU {d} does not have a "model" parameter')
        sensor_list: List[BaseSensor] = []
        for d in value:
            sensor = cast(BaseIMU, InertialMeasurementUnit(d['model']))
            sensor.from_dict(d)
            sensor_list.append(sensor)
        self._imu.set_all(sensor_list)

    # Get All Sensors
    def get_all_sensors(self) -> List[BaseSensor]:
        sensors: List[BaseSensor] = []
        sensors.extend(self.get_all_cameras())
        sensors.extend(self.get_all_gps())
        sensors.extend(self.get_all_imu())
        return sensors

    # Camera: Get All
    def get_all_cameras(self) -> List[BaseCamera]:
        return cast(List[BaseCamera], self._camera.get_all())

    # GPS: Get All
    def get_all_gps(self) -> List[BaseGPS]:
        return cast(List[BaseGPS], self._gps.get_all())

    # IMU: Get All
    def get_all_imu(self) -> List[BaseIMU]:
        return cast(List[BaseIMU], self._imu.get_all())
