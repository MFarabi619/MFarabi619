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
import threading

from ament_index_python.packages import get_package_share_directory
from ament_index_python.search_paths import get_search_paths
from better_launch import BetterLaunch, launch_this
from robot_simulation.view_control import set_view_control_sensitivity


@launch_this
def gz_sim(world: str = 'maize', headless: bool = False):
    bl = BetterLaunch()
    share_directory = get_package_share_directory('robot_simulation')
    worlds_directory = os.path.join(share_directory, 'worlds')
    models_directory = os.path.join(share_directory, 'models')
    share_directories = [
        os.path.join(prefix, 'share') for prefix in get_search_paths()]
    resource_path = os.pathsep.join(
        [worlds_directory, models_directory] + share_directories)
    world_file = os.path.join(worlds_directory, f'{world}.sdf')
    plugin_directory = os.path.join(os.environ.get('CONDA_PREFIX', ''), 'lib')

    def gazebo_exited():
        if not bl.is_shutdown:
            bl.shutdown('gazebo exited, stopping the simulation stack')

    command = ['gz', 'sim', world_file, '-r', '-v', '4']
    env = {
        'GZ_SIM_RESOURCE_PATH': resource_path,
        'GZ_SIM_SYSTEM_PLUGIN_PATH': plugin_directory,
        'OGRE2_RESOURCE_PATH': os.path.join(
            os.environ.get('CONDA_PREFIX', ''), 'lib', 'OGRE-Next'),
    }
    if headless:
        command += ['-s', '--headless-rendering']
        env['DISPLAY'] = ''
        nixos_driver_root = '/run/opengl-driver'
        egl_vendor_directory = os.path.join(nixos_driver_root, 'share/glvnd/egl_vendor.d')
        if os.path.isdir(egl_vendor_directory):
            env['__EGL_VENDOR_LIBRARY_DIRS'] = egl_vendor_directory
            env['LIBGL_DRIVERS_PATH'] = os.path.join(nixos_driver_root, 'lib/dri')
    else:
        command += ['--gui-config', os.path.join(share_directory, 'gui.config')]
        threading.Thread(target=set_view_control_sensitivity, daemon=True).start()
    bl.process(command, name='gazebo', env=env, on_exit=gazebo_exited)
