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

from ament_index_python.packages import get_package_share_directory
from pydantic import BaseModel, ConfigDict, PrivateAttr, ValidationError, model_validator
import yaml

ZED_CAMERA_MODEL = 'zed_2'
ORBBEC_CAMERA_MODEL = 'orbbec_gemini_335l'
OAK_CAMERA_MODELS = ('oak_d_sr', 'oak_d_pro_w_poe')
DEPTH_CAMERA_PRECEDENCE = (OAK_CAMERA_MODELS, (ORBBEC_CAMERA_MODEL,), (ZED_CAMERA_MODEL,))
DRIVETRAIN_MODELS = ('roboteq', 'rc_pulse', 'pwm_dir', 'odrive_usb', 'svd48v')
MOTION_LIMIT_KEYS = (
    'max_linear_velocity_meters_per_second',
    'max_angular_velocity_radians_per_second',
    'max_linear_acceleration_meters_per_second_squared',
    'max_linear_jerk_meters_per_second_cubed',
    'max_angular_acceleration_radians_per_second_squared',
    'max_angular_jerk_radians_per_second_cubed',
)


def source_checkout():
    machines = Path(__file__).resolve().parents[1]
    return machines if any(machines.glob('*/robot.yaml')) else None


def machines_share():
    return source_checkout() or Path(get_package_share_directory('robot_machines'))


def boards_directory():
    checkout = source_checkout()
    if checkout:
        return checkout.parent / 'elec' / 'boards'
    return Path(get_package_share_directory('robot_machines')) / 'boards'


class MachineError(Exception):
    pass


class Record(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Host(Record):
    hostname: str
    ip: str
    board: str


class System(Record):
    hosts: list[Host] = []
    namespace: str = ''


class DrivetrainSide(Record):
    pwm_pin: str | int | None = None
    dir_pin: str | int | None = None
    forward_level: bool | None = None
    is_reversed: bool = False
    serial: str | None = None


class Drivetrain(Record):
    model: str = 'pwm_dir'
    left: DrivetrainSide = DrivetrainSide()
    right: DrivetrainSide = DrivetrainSide()
    serial_port: str | None = None
    baud_rate: int | None = None
    counts_per_revolution: int | None = None
    control_mode: str | None = None
    full_scale_linear_velocity_meters_per_second: float | None = None
    pwm_frequency_hz: float | None = None
    min_duty: float | None = None
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
        return getattr(self, model) if model in DRIVETRAIN_MODELS else {}

    def motion_limits(self, model):
        settings = self.model_settings(model)
        return {
            key: value for key in MOTION_LIMIT_KEYS
            if (value := settings.get(key, getattr(self, key))) is not None}


class RcReceiver(Record):
    channel_1_pin: str | int
    channel_2_pin: str | int
    tank_mixed: bool = False
    launch_enabled: bool = True


class Platform(Record):
    drivetrain: Drivetrain = Drivetrain()
    rc_receiver: RcReceiver | None = None
    attachments: list = []
    collision_guarded: bool = False


class Sensor(Record):
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
    launch_enabled: bool = True
    urdf_enabled: bool = True
    detects_on_camera: bool = False

    @property
    def has_depth(self):
        if self.model == ORBBEC_CAMERA_MODEL:
            return bool(self.parameters.get('enable_depth', False))
        return True

    @property
    def publishes_compressed_color(self):
        return self.model in OAK_CAMERA_MODELS

    @property
    def has_on_camera_detector(self):
        if self.model == 'oak_d_pro_w_poe':
            return self.detects_on_camera
        if self.model == ZED_CAMERA_MODEL:
            return bool(self.parameters.get('object_detection', {}).get('od_enabled', False))
        return False


class Imu(Sensor):
    pass


class Gps(Sensor):
    flash: dict = {}
    ntrip: dict | None = None


class Sensors(Record):
    camera: list[Camera] = []
    imu: list[Imu] = []
    gps: list[Gps] = []

    @model_validator(mode='after')
    def name_sensors_by_index(self):
        for kind in ('camera', 'imu', 'gps'):
            for index, sensor in enumerate(getattr(self, kind)):
                sensor._name = f'{kind}_{index}'
        return self


class Mount(Record):
    parent: str = 'base_link'
    xyz: list[float] = [0.0, 0.0, 0.0]
    rpy: list[float] = [0.0, 0.0, 0.0]


class Mounts(Record):
    camera_mount: list[Mount] = []


class Arm(Record):
    model: str
    gripper: str
    bringup_package: str
    description_package: str
    control_package: str
    moveit_package: str
    moveit_robot_name: str


class Behaviors(Record):
    foxglove: bool = True
    point_cloud: bool = True
    hand_gesture: bool = False
    weeding: bool = False
    follow_nav2: bool = False
    gps_navigation: bool = False
    harvest_lane: bool = False
    line: bool = False
    sidewalk: bool = False
    park_path: bool = False
    path: bool = False

    @model_validator(mode='after')
    def one_nav2_owner(self):
        if self.follow_nav2 and self.gps_navigation:
            raise ValueError(
                'follow_nav2 and gps_navigation both start the nav2 servers; enable one')
        return self


class Machine(Record):
    name: str
    system: System = System()
    platform: Platform | None = None
    arm: Arm | None = None
    sensors: Sensors = Sensors()
    mounts: Mounts = Mounts()
    behaviors: Behaviors = Behaviors()
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
    def has_zed_camera(self):
        return any(camera.model == ZED_CAMERA_MODEL for camera in self.sensors.camera)

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
    def board_pins(self):
        board_path = boards_directory() / f'{self.board}.yaml'
        return yaml.safe_load(board_path.read_text())['pins']

    def params_file(self, component):
        path = machines_share() / self.name / 'params' / f'{component}.yaml'
        return str(path) if path.is_file() else ''


def machine_names(machines_root=None):
    machines_root = machines_root or machines_share()
    return sorted(path.parent.name for path in machines_root.glob('*/robot.yaml'))


def load_machine(name, machines_root=None):
    machines_root = machines_root or machines_share()
    return read_machine(name, machines_root / name / 'robot.yaml')


def load_machine_for_this_host(machines_root=None):
    hostname = socket.gethostname()
    for candidate_name in machine_names(machines_root):
        machine = load_machine(candidate_name, machines_root)
        if any(host.hostname == hostname for host in machine.system.hosts):
            return machine
    raise MachineError(f'no robot.yaml lists hostname {hostname}')


def read_machine(name, path):
    if not path.is_file():
        raise MachineError(f'{name} has no robot.yaml')
    mapping = yaml.safe_load(path.read_text()) or {}
    try:
        return Machine.model_validate({'name': name, **mapping})
    except ValidationError as error:
        raise MachineError(f'{name} robot.yaml: {error}') from error
