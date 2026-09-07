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


from typing import List

from robot_config.common.definitions.accessory import Accessory
from robot_config.sensors.definitions.sensor import BaseSensor


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
            idx: int | None = None,
            name: str | None = None,
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


class AdafruitUltimateGpsHat(BaseGPS):
    SENSOR_MODEL = 'adafruit_ultimate_gps_hat'


class UbloxZedF9p(BaseGPS):
    SENSOR_MODEL = 'ublox_zed_f9p'
