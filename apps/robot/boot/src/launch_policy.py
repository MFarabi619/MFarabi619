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
LIFECYCLE_ACTIVATION = {'lifecycle_waittime': 5.0}
TF_REMAPS = {'/tf': 'tf', '/tf_static': 'tf_static'}
DIAGNOSTICS_REMAPS = {'/diagnostics': 'diagnostics'}
DIAGNOSTIC_AGGREGATOR_REMAPS = DIAGNOSTICS_REMAPS | {
    '/diagnostics_agg': 'diagnostics_agg',
    '/diagnostics_toplevel_state': 'diagnostics_toplevel_state',
}
DEFAULT_DEPTH_FRAMES_PER_SECOND = 15
NAV2_SERVERS = (
    ('nav2_controller', 'controller_server'),
    ('nav2_planner', 'planner_server'),
    ('nav2_bt_navigator', 'bt_navigator'),
)
NAV2_COSTMAPS = ('local_costmap', 'global_costmap')


def include(package, launchfile, **arguments):
    BetterLaunch.instance().include(
        package, launchfile, pass_launch_func_args=False, **arguments)


def write_tempfile(text, suffix):
    with tempfile.NamedTemporaryFile('w', suffix=suffix, delete=False) as text_tempfile:
        text_tempfile.write(text)
    return text_tempfile.name


def write_parameter_overrides_file(overrides_by_node):
    overrides_by_node = {node: values for node, values in overrides_by_node.items() if values}
    if not overrides_by_node:
        return ''
    overrides_tempfile = tempfile.NamedTemporaryFile(
        mode='w', prefix='overrides_', suffix='.yaml', delete=False)
    yaml.safe_dump({
        f'/**/{node}': {'ros__parameters': values}
        for node, values in overrides_by_node.items()
    }, overrides_tempfile)
    overrides_tempfile.close()
    return overrides_tempfile.name
