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


from pathlib import Path
import socket
from typing import Literal, get_args

from ament_index_python.packages import get_package_share_directory
from pydantic import BaseModel, ConfigDict, PrivateAttr, ValidationError, model_validator
import yaml

CameraModel = Literal[
    'luxonis_oak_d_sr', 'luxonis_oak_d_pro_w_poe', 'orbbec_gemini_335l', 'stereolabs_zed']
ImuModel = Literal['adafruit_bno085']
GpsModel = Literal['ublox_zed_f9p']
DrivetrainModel = Literal['roboteq', 'rc_pulse', 'pwm_dir', 'odrive_usb', 'svd48v', 'mock']
ArmModel = Literal['kinova_link6']
CAMERA_MODELS = get_args(CameraModel)
IMU_MODELS = get_args(ImuModel)
GPS_MODELS = get_args(GpsModel)
STEREOLABS_ZED_MODEL = 'stereolabs_zed'
ORBBEC_GEMINI_335L_MODEL = 'orbbec_gemini_335l'
LUXONIS_OAK_D_PRO_W_POE_MODEL = 'luxonis_oak_d_pro_w_poe'
LUXONIS_OAK_MODELS = ('luxonis_oak_d_sr', LUXONIS_OAK_D_PRO_W_POE_MODEL)
DEPTH_CAMERA_PRECEDENCE = (
    LUXONIS_OAK_MODELS, (ORBBEC_GEMINI_335L_MODEL,), (STEREOLABS_ZED_MODEL,))
DRIVETRAIN_MODELS = get_args(DrivetrainModel)
DOMAINS = ('platform', 'sensors', 'perception', 'navigation', 'manipulation')
MOTION_LIMIT_KEYS = (
    'max_linear_velocity_meters_per_second',
    'max_angular_velocity_radians_per_second',
    'max_linear_acceleration_meters_per_second_squared',
    'max_linear_jerk_meters_per_second_cubed',
    'max_angular_acceleration_radians_per_second_squared',
    'max_angular_jerk_radians_per_second_cubed',
)


def machines_source_directory():
    machines = Path(__file__).resolve().parents[1]
    return machines if any(machines.glob('*/robot.yaml')) else None


def machines_directory():
    return machines_source_directory() or Path(get_package_share_directory('robot_machines'))


def boards_directory():
    source = machines_source_directory()
    if source:
        return source.parent / 'elec' / 'boards'
    return Path(get_package_share_directory('robot_machines')) / 'boards'


class MachineError(Exception):
    pass


class StrictRecord(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Host(StrictRecord):
    hostname: str
    ip: str
    board: str


class System(StrictRecord):
    hosts: list[Host] = []
    namespace: str = ''


class DrivetrainSide(StrictRecord):
    pwm_pin: str | int | None = None
    dir_pin: str | int | None = None
    forward_level: bool | None = None
    is_reversed: bool = False
    serial_number: str | None = None


class Drivetrain(StrictRecord):
    model: DrivetrainModel = 'pwm_dir'
    left: DrivetrainSide = DrivetrainSide()
    right: DrivetrainSide = DrivetrainSide()
    serial_port: str | None = None
    baud_rate: int | None = None
    counts_per_revolution: int | None = None
    control_mode: str | None = None
    full_scale_linear_velocity_meters_per_second: float | None = None
    pwm_frequency_hz: float | None = None
    min_duty_fraction: float | None = None
    gear_ratio: float | None = None
    acceleration_rpm_per_second: float | None = None
    speed_smoothing_time: float | None = None
    max_linear_velocity_meters_per_second: float | None = None
    max_angular_velocity_radians_per_second: float | None = None
    max_linear_acceleration_meters_per_second_squared: float | None = None
    max_linear_jerk_meters_per_second_cubed: float | None = None
    max_angular_acceleration_radians_per_second_squared: float | None = None
    max_angular_jerk_radians_per_second_cubed: float | None = None
    roboteq: dict = {}
    rc_pulse: dict = {}
    pwm_dir: dict = {}
    odrive_usb: dict = {}
    svd48v: dict = {}

    def model_settings(self, model):
        return getattr(self, model, {})

    def motion_limits(self, model):
        settings = self.model_settings(model)
        return {
            key: value for key in MOTION_LIMIT_KEYS
            if (value := settings.get(key, getattr(self, key))) is not None}


class RcReceiver(StrictRecord):
    channel_1_pin: str | int
    channel_2_pin: str | int
    tank_mixed: bool = False
    launch_enabled: bool = True


class Platform(StrictRecord):
    drivetrain: Drivetrain = Drivetrain()
    rc_receiver: RcReceiver | None = None
    attachments: list = []
    collision_guarded: bool = False


class Sensor(StrictRecord):
    model: str
    parent: str = 'base_link'
    xyz: list[float] = [0.0, 0.0, 0.0]
    rpy: list[float] = [0.0, 0.0, 0.0]
    parameters: dict = {}
    _name: str = PrivateAttr('')

    @property
    def name(self):
        return self._name


class Camera(Sensor):
    model: CameraModel
    launch_enabled: bool = True
    urdf_enabled: bool = True
    detects_on_camera: bool = False

    @property
    def has_depth(self):
        if self.model == ORBBEC_GEMINI_335L_MODEL:
            return bool(self.parameters.get('enable_depth', False))
        return True

    @property
    def publishes_compressed_color(self):
        return self.model in LUXONIS_OAK_MODELS

    @property
    def has_on_camera_detector(self):
        if self.model == LUXONIS_OAK_D_PRO_W_POE_MODEL:
            return self.detects_on_camera
        if self.model == STEREOLABS_ZED_MODEL:
            return bool(self.parameters.get('object_detection', {}).get('od_enabled', False))
        return False


class Imu(Sensor):
    model: ImuModel


class Gps(Sensor):
    model: GpsModel
    flash: dict = {}
    ntrip: dict | None = None


class Sensors(StrictRecord):
    camera: list[Camera] = []
    imu: list[Imu] = []
    gps: list[Gps] = []

    @model_validator(mode='after')
    def name_sensors_by_index(self):
        for kind in ('camera', 'imu', 'gps'):
            for index, sensor in enumerate(getattr(self, kind)):
                sensor._name = f'{kind}_{index}'
        return self


class Mount(StrictRecord):
    parent: str = 'base_link'
    xyz: list[float] = [0.0, 0.0, 0.0]
    rpy: list[float] = [0.0, 0.0, 0.0]


class Mounts(StrictRecord):
    camera_mount: list[Mount] = []


class Arm(StrictRecord):
    model: ArmModel
    gripper: str
    bringup_package: str
    description_package: str
    control_package: str
    moveit_package: str
    moveit_robot_name: str


class Behaviors(StrictRecord):
    hand_gesture_teleop: bool = False
    weeding: bool = False
    nav2_person_follow: bool = False
    gps_navigation: bool = False
    harvest_lane: bool = False
    line_follow: bool = False
    sidewalk_follow: bool = False
    park_path_follow: bool = False
    path_follow: bool = False

    @model_validator(mode='after')
    def refuse_two_nav2_owners(self):
        if self.nav2_person_follow and self.gps_navigation:
            raise ValueError(
                'nav2_person_follow and gps_navigation both start the nav2 servers; enable one')
        return self


class Machine(StrictRecord):
    name: str
    system: System = System()
    platform: Platform | None = None
    arm: Arm | None = None
    sensors: Sensors = Sensors()
    mounts: Mounts = Mounts()
    behaviors: Behaviors = Behaviors()
    foxglove_enabled: bool = True
    point_cloud_enabled: bool = True
    ros_parameters: dict[str, dict] = {}
    home: dict = {}
    manipulation: dict = {}

    @property
    def namespace(self):
        return self.system.namespace

    @property
    def host(self):
        if not self.system.hosts:
            raise MachineError(f'{self.name} declares no host')
        return self.system.hosts[0]

    @property
    def hostname(self):
        return self.host.hostname

    @property
    def board(self):
        return self.host.board

    @property
    def has_arm(self):
        return self.arm is not None

    @property
    def is_arm_only(self):
        return self.has_arm and self.platform is None

    @property
    def enabled_cameras(self):
        return [camera for camera in self.sensors.camera if camera.launch_enabled]

    @property
    def has_stereolabs_zed(self):
        return any(camera.model == STEREOLABS_ZED_MODEL for camera in self.sensors.camera)

    def first_enabled_camera(self, *models):
        return next(
            (camera for camera in self.enabled_cameras if camera.model in models), None)

    @property
    def depth_camera(self):
        for models in DEPTH_CAMERA_PRECEDENCE:
            camera = self.first_enabled_camera(*models)
            if camera and camera.has_depth:
                return camera
        return None

    @property
    def domains(self):
        sensors = self.sensors
        present = {
            'platform': self.platform is not None,
            'sensors': bool(self.enabled_cameras or sensors.imu or sensors.gps),
            'perception': self.depth_camera is not None,
            'navigation': self.behaviors.nav2_person_follow or self.behaviors.gps_navigation,
            'manipulation': self.has_arm,
        }
        return tuple(domain for domain in DOMAINS if present[domain])

    @property
    def board_pins(self):
        board_path = boards_directory() / f'{self.board}.yaml'
        return yaml.safe_load(board_path.read_text())['pins']


def machine_names(directory=None):
    directory = directory or machines_directory()
    return sorted(path.parent.name for path in directory.glob('*/robot.yaml'))


def load_machine(name, directory=None):
    directory = directory or machines_directory()
    return parse_machine_file(name, directory / name / 'robot.yaml')


def load_machine_for_this_host(directory=None):
    hostname = socket.gethostname()
    for candidate_name in machine_names(directory):
        machine = load_machine(candidate_name, directory)
        if any(host.hostname == hostname for host in machine.system.hosts):
            return machine
    raise MachineError(f'no robot.yaml lists hostname {hostname}')


def parse_machine_file(name, path):
    if not path.is_file():
        raise MachineError(f'{name} has no robot.yaml')
    mapping = yaml.safe_load(path.read_text()) or {}
    try:
        return Machine.model_validate({'name': name, **mapping})
    except ValidationError as error:
        raise MachineError(f'{name} robot.yaml: {error}') from error
