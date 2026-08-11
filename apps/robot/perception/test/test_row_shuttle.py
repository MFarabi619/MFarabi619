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


import math
from types import SimpleNamespace

import py_trees
import pytest

from conftest import load_module


@pytest.fixture(scope='module')
def row_shuttle():
    return load_module('row_shuttle')


def test_pass_runs_follow_clear_turn(row_shuttle):
    names = [child.name for child in row_shuttle.shuttle_pass().children]
    assert names == ['acquire_and_follow_row', 'clear_headland', 'turn_around']


def test_follow_row_abort_retries_instead_of_failing_the_mission(row_shuttle):
    acquire = row_shuttle.acquire_and_follow_row()
    assert isinstance(acquire, py_trees.decorators.FailureIsRunning)
    assert acquire.decorated.name == 'follow_row'


def test_mission_repeats_indefinitely(row_shuttle):
    root = row_shuttle.mission()
    assert root.num_success == -1
    assert root.decorated.name == 'shuttle_pass'


def test_clearance_spans_footprint_pivot_and_lost_point(row_shuttle):
    assert row_shuttle.HEADLAND_CLEARANCE_M == pytest.approx(2.71, abs=0.01)


def stub_tree(status):
    return SimpleNamespace(
        root=SimpleNamespace(status=status),
        timer=SimpleNamespace(canceled=False))


def test_failed_mission_stops_ticking(row_shuttle):
    tree = stub_tree(py_trees.common.Status.FAILURE)
    tree.timer.cancel = lambda: setattr(tree.timer, 'canceled', True)
    row_shuttle.halt_when_failed(tree)
    assert tree.timer.canceled


def test_running_mission_keeps_ticking(row_shuttle):
    tree = stub_tree(py_trees.common.Status.RUNNING)
    tree.timer.cancel = lambda: setattr(tree.timer, 'canceled', True)
    row_shuttle.halt_when_failed(tree)
    assert not tree.timer.canceled


def test_clear_goal_drives_the_clearance_distance(row_shuttle):
    goal = row_shuttle.clear_headland_goal()
    assert goal.target.x == pytest.approx(row_shuttle.HEADLAND_CLEARANCE_M)
    assert goal.speed == pytest.approx(row_shuttle.CLEAR_SPEED_MPS)


def test_turn_goal_spins_just_short_of_half_turn(row_shuttle):
    goal = row_shuttle.turn_around_goal()
    assert goal.target_yaw == pytest.approx(math.pi - row_shuttle.TURN_SHORTFALL_RAD)
