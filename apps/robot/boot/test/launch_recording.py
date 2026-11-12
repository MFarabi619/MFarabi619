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


import contextlib
import glob
import importlib.util
import os
import socket
import subprocess
import sys
import tempfile
import time
import types

import ament_index_python.packages
import ament_index_python.search_paths
import pytest
import yaml

ROBOT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
REPO_ROOT = os.path.abspath(os.path.join(ROBOT_ROOT, '..', '..'))
PYTHON_SOURCE_DIRECTORIES = {
    'robot_boot': os.path.join(ROBOT_ROOT, 'boot', 'src'),
    'robot_simulation': os.path.join(ROBOT_ROOT, 'simulation', 'src'),
    'robot_machines': os.path.join(ROBOT_ROOT, 'machines', 'src'),
}
AMENT_PACKAGE_DIRECTORIES = {
    'robot_description': os.path.join(ROBOT_ROOT, 'mech'),
    'robot_control': os.path.join(ROBOT_ROOT, 'control'),
    'robot_boot': os.path.join(ROBOT_ROOT, 'boot'),
    'robot_drivers': os.path.join(ROBOT_ROOT, 'drivers'),
    'robot_perception': os.path.join(ROBOT_ROOT, 'perception'),
    'robot_navigation': os.path.join(ROBOT_ROOT, 'navigation'),
    'robot_manipulation': os.path.join(ROBOT_ROOT, 'manipulation'),
    'robot_simulation': os.path.join(ROBOT_ROOT, 'simulation'),
    'zed_wrapper': os.path.join(REPO_ROOT, 'vendor', 'zed-ros2-wrapper', 'zed_wrapper'),
}


class RecordedNode:
    def __init__(self, event):
        self.event = event
        self.name = event.get('name')

    def join(self):
        return 0


class LaunchRecorder:
    def __init__(self, temporary_directory):
        self.temporary_directory = temporary_directory
        self.environment_before = dict(os.environ)
        self.events = []
        self.group_stack = []
        self.composer_name = None

    @property
    def namespace(self):
        return '/' + '/'.join(self.group_stack)

    @property
    def is_shutdown(self):
        return False

    @property
    def group_tip(self):
        return types.SimpleNamespace(assemble_namespace=lambda: self.namespace)

    def zenoh_router_is_recorded(self):
        return any(
            event.get('executable') == self.zenoh_router_executable
            for event in self.events)

    def record(self, kind, **fields):
        event = {'kind': kind, 'namespace': self.namespace, **fields}
        self.events.append(event)
        return event

    @contextlib.contextmanager
    def group(self, namespace, use_sim_time=None):
        group_stack_before = self.group_stack[:]
        if namespace.startswith('/'):
            self.group_stack = []
        self.group_stack += filter(None, namespace.split('/'))
        self.record('group', group=namespace, use_sim_time=use_sim_time)
        try:
            yield self.namespace
        finally:
            self.group_stack = group_stack_before

    def node(self, package, executable, name=None, **kwargs):
        return RecordedNode(
            self.record('node', package=package, executable=executable, name=name, **kwargs))

    def process(self, cmd, name=None, **kwargs):
        return RecordedNode(self.record('process', cmd=cmd, name=name, **kwargs))

    @contextlib.contextmanager
    def compose(self, name=None, language='cpp', variant='normal', **kwargs):
        self.record('compose', name=name, language=language, variant=variant, **kwargs)
        self.composer_name = name
        try:
            yield name
        finally:
            self.composer_name = None

    def component(self, package, plugin, name=None, **kwargs):
        assert self.composer_name is not None, 'component outside compose()'
        return self.record(
            'component', container=self.composer_name, package=package, plugin=plugin,
            name=name, **kwargs)

    def include(self, package, launchfile, subdir=None, pass_launch_func_args=True, **arguments):
        self.record(
            'include', package=package, launchfile=launchfile, subdir=subdir,
            arguments=arguments)
        if package in AMENT_PACKAGE_DIRECTORIES:
            module = load_launch(self.find(package, launchfile, subdir))
            launch_function(module)(**arguments)

    def wait_for_service(self, service, timeout=None):
        self.record('wait_for_service', service=service, timeout=timeout)
        return True

    def wait_for_topic(self, topic, timeout=None):
        self.record('wait_for_topic', topic=topic, timeout=timeout)
        return True

    def find(self, package=None, filename=None, subdir='**'):
        if filename and os.path.isabs(filename):
            return filename
        package_name = (package or '').partition('/')[0]
        if package_name in AMENT_PACKAGE_DIRECTORIES:
            pattern = os.path.join(
                AMENT_PACKAGE_DIRECTORIES[package_name], '**', subdir or '**', filename)
            matches = glob.glob(pattern, recursive=True)
            if matches:
                return matches[0]
        return f'<find:{package}/{filename}>'

    def load_params(self, package=None, configfile=None, subdir=None, **_):
        with open(self.find(package, configfile, subdir)) as file:
            return yaml.safe_load(file)

    def shutdown(self, reason=None, *_, **__):
        self.record('shutdown', reason=reason)

    def __getattr__(self, attribute):
        raise AttributeError(
            f'BetterLaunch.{attribute} is not recorded; extend boot/test/launch_recording.py')


def fake_better_launch(recorder):
    class BetterLaunch:
        def __new__(cls, *_, **__):
            return recorder

        @classmethod
        def instance(cls):
            return recorder

    def launch_this(decorated=None, **settings):
        def decorate(function):
            function.launch_this_settings = settings
            return function
        return decorate if decorated is None else decorate(decorated)

    package = types.ModuleType('better_launch')
    package.__path__ = []
    package.BetterLaunch = BetterLaunch
    package.launch_this = launch_this

    convenience = types.ModuleType('better_launch.convenience')

    def read_robot_description(package, description_file, subdir=None, *, xacro_args=None):
        path = recorder.find(package, description_file, subdir)
        if not os.path.isfile(path):
            return f'<robot_description {path} {" ".join(xacro_args or [])}>'
        assert path.endswith('.urdf') and xacro_args is None, 'xacro is not recorded'
        with open(path) as file:
            return file.read()

    def robot_state_publisher(robot_description=None, *, node_name=None, anonymous=True,
                              xacro_args=None, pass_by_topic=False,
                              description_topic='/robot_description', **kwargs):
        params = kwargs.pop('params', {})
        remaps = kwargs.pop('remaps', {})
        return recorder.node(
            'robot_state_publisher', 'robot_state_publisher', node_name,
            anonymous=anonymous, xacro_args=xacro_args,
            params={'robot_description': robot_description or description_topic, **params},
            remaps=remaps, **kwargs)

    convenience.read_robot_description = read_robot_description
    convenience.robot_state_publisher = robot_state_publisher

    gazebo = types.ModuleType('better_launch.gazebo')

    class GazeboBridge:
        def __init__(self, topic, ros2_type=None, direction='bidirectional', gazebo_type=None,
                     *, remaps=None):
            self.topic = topic
            self.ros2_type = ros2_type
            self.direction = direction
            self.gazebo_type = gazebo_type
            self.remaps = remaps

        @classmethod
        def clock_bridge(cls):
            return cls('/clock', 'rosgraph_msgs/msg/Clock', 'gz2ros')

    def get_gazebo_axes_args(x=0.0, y=0.0, z=0.0, yaw=0.0, pitch=0.0, roll=0.0):
        return {'x': x, 'y': y, 'z': z, 'Y': yaw, 'P': pitch, 'R': roll}

    def spawn_model(model_name, model, model_source='auto', spawn_args=None, **kwargs):
        return recorder.record(
            'spawn_model', model_name=model_name, model=model, model_source=model_source,
            spawn_args=spawn_args or {}, **kwargs)

    def spawn_topic_bridge(*bridges, node_name='gz_bridge', **kwargs):
        return recorder.record(
            'topic_bridge', name=node_name, bridges=[vars(bridge) for bridge in bridges],
            **kwargs)

    def spawn_image_bridge(*bridges, node_name=None, **kwargs):
        return recorder.record('image_bridge', name=node_name, bridges=list(bridges), **kwargs)

    gazebo.GazeboBridge = GazeboBridge
    gazebo.get_gazebo_axes_args = get_gazebo_axes_args
    gazebo.spawn_model = spawn_model
    gazebo.spawn_topic_bridge = spawn_topic_bridge
    gazebo.spawn_image_bridge = spawn_image_bridge

    package.convenience = convenience
    package.gazebo = gazebo
    return {
        'better_launch': package,
        'better_launch.convenience': convenience,
        'better_launch.gazebo': gazebo,
    }


def isolate_launch_environment(recorder, monkeypatch):
    for name, module in fake_better_launch(recorder).items():
        monkeypatch.setitem(sys.modules, name, module)
    for name in list(sys.modules):
        if name.partition('.')[0] in PYTHON_SOURCE_DIRECTORIES:
            monkeypatch.delitem(sys.modules, name)
    for name, directory in PYTHON_SOURCE_DIRECTORIES.items():
        monkeypatch.setitem(sys.modules, name, import_source_package(name, directory))
    monkeypatch.chdir(ROBOT_ROOT)
    monkeypatch.setattr(tempfile, 'tempdir', recorder.temporary_directory)
    monkeypatch.setattr(socket, 'gethostname', lambda: 'snapshot-host')
    monkeypatch.setenv('ZED_SDK_ROOT', ROBOT_ROOT)
    monkeypatch.setattr(time, 'sleep', lambda seconds: pytest.fail(f'launch slept {seconds}s'))

    def record_subprocess(argv, *_, **__):
        recorder.record('subprocess', argv=list(argv))
        return subprocess.CompletedProcess(argv, 0, '', '')

    monkeypatch.setattr(subprocess, 'run', record_subprocess)
    monkeypatch.setattr(
        ament_index_python.packages, 'get_package_share_directory',
        AMENT_PACKAGE_DIRECTORIES.__getitem__)
    monkeypatch.setattr(ament_index_python.search_paths, 'get_search_paths', lambda: [])
    from robot_boot import zenoh_router
    recorder.zenoh_router_executable = zenoh_router.ZENOH_ROUTER_EXECUTABLE
    monkeypatch.setattr(
        zenoh_router, 'zenoh_router_is_listening', recorder.zenoh_router_is_recorded)
    monkeypatch.setattr(zenoh_router, 'wait_for_zenoh_router', lambda *_, **__: True)


def import_source_package(name, directory):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(directory, '__init__.py'), submodule_search_locations=[directory])
    package = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(package)
    return package


def load_launch(path):
    path = os.path.join(ROBOT_ROOT, path)
    module_name = os.path.basename(path).replace('.', '_').replace('-', '_')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def launch_function(module):
    return next(
        attribute for attribute in vars(module).values()
        if hasattr(attribute, 'launch_this_settings'))
