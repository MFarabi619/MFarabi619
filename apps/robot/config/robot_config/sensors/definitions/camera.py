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


class BaseCamera(BaseSensor):
    SENSOR_TYPE = 'camera'
    SENSOR_MODEL = 'base'
    TOPIC = 'image'

    class TOPICS:
        COLOR_IMAGE = 'color_image'
        COLOR_CAMERA_INFO = 'color_camera_info'
        NAME = {
            COLOR_IMAGE: 'color/image',
            COLOR_CAMERA_INFO: 'color/camera_info'
        }
        TYPE = {
            COLOR_IMAGE: 'sensor_msgs/msg/Image',
            COLOR_CAMERA_INFO: 'sensor_msgs/msg/CameraInfo',
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


class IMX296GS(BaseCamera):
    SENSOR_MODEL = 'imx296_gs'


class USBWebcam(BaseCamera):
    SENSOR_MODEL = 'usb_webcam'


class OrbbecGemini335L(BaseCamera):
    SENSOR_MODEL = 'orbbec_gemini_335l'
