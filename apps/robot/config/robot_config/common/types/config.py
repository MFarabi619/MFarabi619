from typing import Any

from robot_config.common.types.namespace import Namespace
from robot_config.common.types.serial_number import SerialNumber
from robot_config.common.utils.dictionary import (
    flatten_dict,
    get_from_dict,
    is_in_dict,
    set_in_dict,
    unflatten_dict
)


class BaseConfig:
    _SERIAL_NUMBER = SerialNumber('generic')
    _NAMESPACE = Namespace()
    _VERSION = 0
    DLIM = '.'

    def __init__(
            self,
            template: dict,
            config: dict = {},
            parent_key: str = None,
            ) -> None:
        # Dictionaries are Stored Flat
        self._config = {}
        self.template = template
        self._parent_key = parent_key
        if self._parent_key is not None and self._parent_key not in config:
            self._config = {self._parent_key: {}}
        self.config = config

    def update(
            self,
            serial_number=False,
            ) -> None:
        """Update any variables based on inputs."""
        return

    @property
    def template(self) -> dict:
        """Return template configuration dictionary."""
        return self._template

    @template.setter
    def template(self, value: dict) -> None:
        if not isinstance(value, dict):
            raise TypeError(f'Template must be of type "dict" not "{type(value)}"')
        # Check that template has all properties
        flat_template = flatten_dict(d=value, dlim=BaseConfig.DLIM)
        for key, val in flat_template.items():
            if not isinstance(val, property):
                raise ValueError(f'Template value at {key} must be a property')
        self._template = value

    @property
    def config(self) -> dict:
        """Return configuration dictionary."""
        for _, prop in flatten_dict(
                d=self.template, dlim=BaseConfig.DLIM).items():
            self.getter(prop)()
        return self._config

    @config.setter
    def config(self, value: dict) -> None:
        if value is None:
            return
        if not isinstance(value, dict):
            raise TypeError(f'Config must be of type "dict", not "{type(value)}"')
        if self._parent_key is not None and self._parent_key not in value:
            value = {self._parent_key: value}
        value = unflatten_dict(value)
        for map, prop in flatten_dict(  # noqa:A001
                d=self.template, dlim=BaseConfig.DLIM).items():
            keys = map.split(BaseConfig.DLIM)
            if is_in_dict(value, keys):
                self.setter(prop)(get_from_dict(value, keys))

    def setter(self, prop: property):
        return prop.fset.__get__(self)

    def getter(self, prop: property):
        return prop.fget.__get__(self)

    def set_config_param(self, key: str, value: Any) -> None:
        keys = key.split(BaseConfig.DLIM)
        set_in_dict(d=self._config, map=keys, val=value)

    @classmethod
    def get_serial_number(cls, prefix: bool = False) -> str:
        return BaseConfig._SERIAL_NUMBER.get_serial(prefix=prefix)

    @classmethod
    def set_serial_number(cls, sn: str) -> None:
        BaseConfig._SERIAL_NUMBER = SerialNumber(sn)

    @classmethod
    def get_unit_number(cls) -> str:
        return BaseConfig._SERIAL_NUMBER.get_unit()

    @classmethod
    def get_platform_model(cls) -> str:
        return BaseConfig._SERIAL_NUMBER.get_model()

    @classmethod
    def get_namespace(cls) -> str:
        return str(BaseConfig._NAMESPACE)

    @classmethod
    def set_namespace(cls, namespace: str | Namespace) -> None:
        if isinstance(namespace, Namespace):
            BaseConfig._NAMESPACE = namespace
        elif isinstance(namespace, str):
            BaseConfig._NAMESPACE = Namespace(namespace)
        else:
            if not (isinstance(namespace, str) or isinstance(namespace, Namespace)):
                raise TypeError('Namespace {namespace} must be of type "str" or "Namespace"')
