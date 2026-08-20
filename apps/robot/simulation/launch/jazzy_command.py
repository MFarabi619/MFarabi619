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


import os


def jazzy_command(name, executable_path, arguments, namespace=''):
    environment_path = os.path.abspath('.pixi/envs/jazzy')
    namespace_arg = f' -r __ns:=/{namespace}' if namespace else ''
    return ('pixi run --clean-env -e jazzy'
            f' {environment_path}/lib/{executable_path}'
            f' --ros-args -r __node:={name}{namespace_arg} {arguments} -p use_sim_time:=true')


def jazzy_environment():
    return {'HOME': os.environ['HOME'], 'PATH': os.environ['PATH']}


def behavior_server_command(namespace=''):
    return jazzy_command(
        'behavior_server', 'nav2_behaviors/behavior_server',
        '--params-file navigation/config/behaviors.yaml', namespace)


def behavior_lifecycle_manager_command(namespace=''):
    return jazzy_command(
        'behavior_lifecycle_manager', 'nav2_lifecycle_manager/lifecycle_manager',
        '-p autostart:=true -p node_names:=[behavior_server] -p bond_timeout:=0.0', namespace)
