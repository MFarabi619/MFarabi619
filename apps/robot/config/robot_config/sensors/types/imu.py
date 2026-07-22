from typing import List

from robot_config.common.types.accessory import Accessory
from robot_config.sensors.types.sensor import BaseSensor


class BaseIMU(BaseSensor):
    SENSOR_TYPE = 'imu'
    SENSOR_MODEL = 'base'
    TOPIC = 'data'

    class TOPICS:
        DATA = 'data'
        NAME = {
            DATA: 'data',
        }
        TYPE = {
            DATA: 'sensor_msgs/msg/Imu',
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
            BaseIMU.TOPICS.DATA: 50,
        }


class Bno085(BaseIMU):
    SENSOR_MODEL = 'bno085'
