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


from dataclasses import dataclass, field, fields, is_dataclass
from pathlib import Path
import socket
import types
import typing

import yaml

SCHEMA_VERSION = 1
ZED_CAMERA_MODEL = 'zed_2'
DRIVETRAIN_MODELS = ('roboteq', 'rc_pulse', 'pwm_dir', 'odrive_usb', 'svd48v')
MOTION_LIMIT_KEYS = (
    'max_linear_velocity_meters_per_second',
    'max_angular_velocity_radians_per_second',
    'max_linear_acceleration_meters_per_second_squared',
    'max_linear_jerk_meters_per_second_cubed',
    'max_angular_acceleration_radians_per_second_squared',
    'max_angular_jerk_radians_per_second_cubed',
)


def robot_root():
    source_root = Path(__file__).resolve().parent.parent
    if (source_root / 'machines' / 'machine.py').is_file():
        return source_root
    return Path.cwd()


class MachineError(Exception):
    pass


@dataclass
class Host:
    hostname: str
    ip: str
    board: str


@dataclass
class System:
    hosts: list[Host] = field(default_factory=list)
    namespace: str = ''


@dataclass
class DrivetrainSide:
    pwm_pin: str | int | None = None
    dir_pin: str | int | None = None
    forward_level: bool | None = None
    is_reversed: bool = False
    serial: str | None = None


@dataclass
class Drivetrain:
    model: str = 'pwm_dir'
    left: DrivetrainSide = field(default_factory=DrivetrainSide)
    right: DrivetrainSide = field(default_factory=DrivetrainSide)
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
    roboteq: dict = field(default_factory=dict)
    rc_pulse: dict = field(default_factory=dict)
    pwm_dir: dict = field(default_factory=dict)
    odrive_usb: dict = field(default_factory=dict)
    svd48v: dict = field(default_factory=dict)

    def model_settings(self, model):
        return getattr(self, model) if model in DRIVETRAIN_MODELS else {}

    def motion_limits(self, model):
        settings = self.model_settings(model)
        return {
            key: value for key in MOTION_LIMIT_KEYS
            if (value := settings.get(key, getattr(self, key))) is not None}


@dataclass
class RcReceiver:
    channel_1_pin: str | int
    channel_2_pin: str | int
    tank_mixed: bool = False
    launch_enabled: bool = True


@dataclass
class Platform:
    drivetrain: Drivetrain = field(default_factory=Drivetrain)
    rc_receiver: RcReceiver | None = None
    attachments: list = field(default_factory=list)
    collision_guarded: bool = False


@dataclass
class Sensor:
    model: str
    parent: str = 'base_link'
    xyz: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    rpy: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    ros_parameters: dict[str, dict] = field(default_factory=dict)

    @property
    def node_name(self):
        return next(iter(self.ros_parameters))

    @property
    def node_parameters(self):
        return next(iter(self.ros_parameters.values()), {})


@dataclass
class Camera(Sensor):
    launch_enabled: bool = True
    urdf_enabled: bool = True
    detects_on_camera: bool = False


@dataclass
class Imu(Sensor):
    pass


@dataclass
class Gps(Sensor):
    flash: dict = field(default_factory=dict)
    ntrip: dict | None = None


@dataclass
class Sensors:
    camera: list[Camera] = field(default_factory=list)
    imu: list[Imu] = field(default_factory=list)
    gps: list[Gps] = field(default_factory=list)


@dataclass
class Mount:
    parent: str = 'base_link'
    xyz: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    rpy: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])


@dataclass
class Mounts:
    camera_mount: list[Mount] = field(default_factory=list)


@dataclass
class Arm:
    model: str
    gripper: str
    bringup_package: str
    description_package: str
    control_package: str
    moveit_package: str
    moveit_robot_name: str


@dataclass
class Machine:
    name: str
    serial_number: str
    version: int
    system: System = field(default_factory=System)
    platform: Platform | None = None
    arm: Arm | None = None
    sensors: Sensors = field(default_factory=Sensors)
    mounts: Mounts = field(default_factory=Mounts)
    manipulation: dict = field(default_factory=dict)
    point_cloud: dict = field(default_factory=dict)
    foxglove: dict = field(default_factory=dict)
    detector: dict = field(default_factory=dict)
    follow: dict = field(default_factory=dict)
    follow_nav2: dict = field(default_factory=dict)
    gps_navigation: dict = field(default_factory=dict)
    home: dict = field(default_factory=dict)
    hand_gesture: dict = field(default_factory=dict)
    harvest_lane: dict = field(default_factory=dict)
    line: dict = field(default_factory=dict)
    sidewalk: dict = field(default_factory=dict)
    park_path: dict = field(default_factory=dict)
    path: dict = field(default_factory=dict)

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

    def first_enabled_camera(self, model):
        return next(
            (camera for camera in self.enabled_cameras if camera.model == model), None)

    @property
    def urdf_path(self):
        return robot_root() / 'mech' / 'urdf' / self.name / 'robot.urdf'


def machine_names(machines_root=None):
    machines_root = machines_root or robot_root() / 'machines'
    return sorted(path.parent.name for path in machines_root.glob('*/robot.yaml'))


def load_machine(name, machines_root=None):
    machines_root = machines_root or robot_root() / 'machines'
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
    if mapping.get('version', 0) < SCHEMA_VERSION:
        raise MachineError(
            f'{name} robot.yaml is schema version {mapping.get("version", 0)};'
            f' version {SCHEMA_VERSION} resolves wiring through elec/boards/')
    return build_record(Machine, {'name': name, **mapping}, name)


def build_record(record_type, mapping, location):
    if not isinstance(mapping, dict):
        raise MachineError(f'{location}: expected a mapping, found {mapping!r}')
    type_hints = {attribute.name: attribute.type for attribute in fields(record_type)}
    unknown_keys = sorted(set(mapping) - type_hints.keys())
    if unknown_keys:
        raise MachineError(f'{location}: unknown keys {unknown_keys}')
    values = {
        key: convert_field(type_hints[key], value, f'{location}.{key}')
        for key, value in mapping.items()}
    try:
        return record_type(**values)
    except TypeError as error:
        raise MachineError(f'{location}: {error}') from error


def convert_field(annotation, value, location):
    if is_dataclass(annotation):
        return build_record(annotation, value or {}, location)
    origin = typing.get_origin(annotation)
    arguments = typing.get_args(annotation)
    if origin is list and arguments and is_dataclass(arguments[0]):
        return [
            build_record(arguments[0], item, f'{location}[{index}]')
            for index, item in enumerate(value or [])]
    if origin is types.UnionType:
        nested = [argument for argument in arguments if is_dataclass(argument)]
        if nested and value is not None:
            return build_record(nested[0], value, location)
    return value
