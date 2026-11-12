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


import tempfile

from better_launch import BetterLaunch
import yaml

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}
TF_REMAPS = {'/tf': 'tf', '/tf_static': 'tf_static'}


def include(package, launchfile, **arguments):
    BetterLaunch.instance().include(
        package, launchfile, pass_launch_func_args=False, **arguments)


def parameter_overrides_file(overrides_by_node):
    overrides_by_node = {node: values for node, values in overrides_by_node.items() if values}
    if not overrides_by_node:
        return ''
    overrides = tempfile.NamedTemporaryFile(
        mode='w', prefix='overrides_', suffix='.yaml', delete=False)
    yaml.safe_dump({
        f'/**/{node}': {'ros__parameters': values}
        for node, values in overrides_by_node.items()
    }, overrides)
    overrides.close()
    return overrides.name
