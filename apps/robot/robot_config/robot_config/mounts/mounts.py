from typing import List

from robot_config.common.types.config import BaseConfig
from robot_config.common.types.list import OrderedListConfig
from robot_config.common.utils.dictionary import flip_dict
from robot_config.mounts.types.mount import BaseMount, CameraMount


class Mount():
    CAMERA_MOUNT = CameraMount.MOUNT_MODEL

    MODEL = {
        CAMERA_MOUNT: CameraMount,
    }

    def __new__(cls, model: str) -> BaseMount:
        if model not in Mount.MODEL:
            raise ValueError(f'Model "{model}" must be one of "{Mount.MODEL.keys()}"')
        return Mount.MODEL[model]()


class MountListConfig(OrderedListConfig[BaseMount]):

    def __init__(self) -> None:
        super().__init__(obj_type=BaseMount)

    def to_dict(self) -> List[dict]:
        d = []
        for accessory in self.get_all():
            d.append(accessory.to_dict())
        return d


class MountsConfig(BaseConfig):

    MOUNTS = 'mounts'
    CAMERA_MOUNT = CameraMount.MOUNT_MODEL

    TEMPLATE = {
        MOUNTS: {
            CAMERA_MOUNT: CAMERA_MOUNT,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS = {
        CAMERA_MOUNT: [],
    }

    def __init__(
            self,
            config: dict = {},
            camera_mount: List[CameraMount] = DEFAULTS[CAMERA_MOUNT],
            ) -> None:
        # Initialization
        self.camera_mount = camera_mount
        # Template
        template = {
            self.KEYS[self.CAMERA_MOUNT]: MountsConfig.camera_mount,
        }
        super().__init__(template, config, self.MOUNTS)

    @property
    def camera_mount(self) -> OrderedListConfig:
        self.set_config_param(
            key=self.KEYS[self.CAMERA_MOUNT],
            value=self._camera_mount.to_dict()
        )
        return self._camera_mount

    @camera_mount.setter
    def camera_mount(self, value: List[dict]) -> None:
        if not isinstance(value, list):
            raise TypeError(f'Camera mounts must be list of "dict". Got {value}')
        for i in value:
            if not isinstance(i, dict):
                raise TypeError(f'Camera mount {i} must be of type "dict"')
        mounts = MountListConfig()
        mount_list = []
        for d in value:
            mount = CameraMount()
            mount.from_dict(d)
            mount_list.append(mount)
        mounts.set_all(mount_list)
        self._camera_mount = mounts

    # Get All Mounts
    def get_all_mounts(self) -> List[BaseMount]:
        mounts = []
        mounts.extend(self.camera_mount.get_all())
        return mounts
