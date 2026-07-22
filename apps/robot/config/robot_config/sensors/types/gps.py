from typing import List

from robot_config.common.types.accessory import Accessory
from robot_config.sensors.types.sensor import BaseSensor


class BaseGPS(BaseSensor):
    SENSOR_TYPE = 'gps'
    SENSOR_MODEL = 'base'
    TOPIC = 'fix'

    class TOPICS:
        FIX = 'fix'
        NAME = {
            FIX: 'fix',
        }
        TYPE = {
            FIX: 'sensor_msgs/msg/NavSatFix',
        }

    def __init__(
            self,
            idx: int = None,
            name: str = None,
            topic: str = TOPIC,
            urdf_enabled: bool = BaseSensor.URDF_ENABLED,
            launch_enabled: bool = BaseSensor.LAUNCH_ENABLED,
            ros_parameters: dict = BaseSensor.ROS_PARAMETERS,
            ros_parameters_template: dict = BaseSensor.ROS_PARAMETERS_TEMPLATE,
            parent: str = Accessory.PARENT,
            xyz: List[float] = Accessory.XYZ,
            rpy: List[float] = Accessory.RPY
            ) -> None:
        super().__init__(
            idx,
            name,
            topic,
            urdf_enabled,
            launch_enabled,
            ros_parameters,
            ros_parameters_template,
            parent,
            xyz,
            rpy,
        )
        # Topic Rates
        self.rates = {
            BaseGPS.TOPICS.FIX: 1,
        }


class Gpsd(BaseGPS):
    SENSOR_MODEL = 'gpsd'
