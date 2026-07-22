from typing import List

from robot_config.common.types.config import BaseConfig
from robot_config.common.types.namespace import Namespace
from robot_config.common.utils.dictionary import flip_dict
from robot_config.system.hosts import HostConfig, HostListConfig


class SystemConfig(BaseConfig):

    SYSTEM = 'system'
    HOSTS = 'hosts'
    NAMESPACE = 'namespace'

    TEMPLATE = {
        SYSTEM: {
            HOSTS: HOSTS,
            NAMESPACE: NAMESPACE,
        }
    }

    KEYS = flip_dict(TEMPLATE)

    DEFAULTS = {
        # HOSTS: hostnames and IP's for all computers involved with the system
        HOSTS: HostListConfig.DEFAULTS,
        # NAMESPACE: robot namespace, empty by default
        NAMESPACE: '',
    }

    def __init__(
            self,
            config: dict = {},
            hosts: List[dict] | HostListConfig = DEFAULTS[HOSTS],
            namespace: str | Namespace = DEFAULTS[NAMESPACE],
            ) -> None:
        # Initialization
        self._config = {}
        self.hosts = hosts
        self.namespace = namespace
        # Setter Template
        setters = {
            self.KEYS[self.HOSTS]: SystemConfig.hosts,
            self.KEYS[self.NAMESPACE]: SystemConfig.namespace,
        }
        # Set from Config
        super().__init__(setters, config, self.SYSTEM)

    @property
    def hosts(self) -> HostListConfig:
        self.set_config_param(
            key=self.KEYS[self.HOSTS],
            value=self._hosts.to_dict()
        )
        return self._hosts

    @hosts.setter
    def hosts(self, value: List[dict] | HostListConfig) -> None:
        host_list = []
        if isinstance(value, list):
            for d in value:
                if not isinstance(d, dict):
                    raise TypeError(f'Host value of {d} is invalid, it must be of type "dict"')
                host_list.append(HostConfig(config=d))

            for host in host_list:
                # Ensure no duplicate hostname or IP
                count = sum(((host.ip_address == h.ip_address) or (host.hostname == h.hostname))
                            for h in host_list)
                if count != 1:
                    raise ValueError(
                        f'Host {host} conflicts with another host. Each hostname and ip must be unique.'  # noqa: E501
                    )

            self._hosts = HostListConfig()
            self._hosts.set_all(host_list)
        elif isinstance(value, HostListConfig):
            self._hosts = value
        else:
            if not (isinstance(value, list) or isinstance(value, HostConfig)):
                raise TypeError(
                    f'Hosts value of {value} is invalid, it must be of type "List[dict]" or "HostListConfig"'  # noqa: E501
                )

    @property
    def namespace(self) -> str:
        self.set_config_param(
            key=self.KEYS[self.NAMESPACE],
            value=self._namespace
        )
        return self._namespace

    @namespace.setter
    def namespace(self, value: str | Namespace) -> None:
        # An empty namespace is the robot root; only validate non-empty values
        if value == '':
            self._namespace = ''
        elif isinstance(value, Namespace):
            self._namespace = str(value)
        elif isinstance(value, str):
            self._namespace = str(Namespace(value))
        else:
            raise TypeError(f'Namespace {value} must be of type "str" or "Namespace"')
