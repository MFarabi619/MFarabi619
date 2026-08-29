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


import ast
import importlib.util
import math
import os
import re
import sys

import pytest

SIMULATION_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LAUNCH_DIR = os.path.join(SIMULATION_DIR, 'launch')
SPAWN_TOLERANCE_M = 0.05


@pytest.fixture(scope='module')
def farm_generator():
    path = os.path.join(SIMULATION_DIR, 'farm_generator.py')
    if SIMULATION_DIR not in sys.path:
        sys.path.insert(0, SIMULATION_DIR)
    spec = importlib.util.spec_from_file_location('farm_generator', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='module')
def launch_constants():
    source = ast.parse(open(os.path.join(LAUNCH_DIR, 'simulation.launch.py')).read())
    constants = {}
    for statement in source.body:
        if isinstance(statement, ast.Assign) and isinstance(statement.targets[0], ast.Name):
            try:
                constants[statement.targets[0].id] = ast.literal_eval(statement.value)
            except ValueError:
                continue
    return constants


def upward_triangle_count(mesh):
    upward = 0
    for first, second, third in mesh.triangles:
        origin = mesh.positions[first]
        edge_a = [mesh.positions[second][axis] - origin[axis] for axis in range(3)]
        edge_b = [mesh.positions[third][axis] - origin[axis] for axis in range(3)]
        if edge_a[0] * edge_b[1] - edge_a[1] * edge_b[0] > 0.0:
            upward += 1
    return upward


def walkable_surfaces(farm_generator):
    """Horizontal surfaces only, built from the generator's own constants so a
    constant change cannot leave the test asserting stale numbers."""
    segments = farm_generator.centerline_frames(farm_generator.road_centerline())
    half_road = farm_generator.ROAD_WIDTH / 2.0
    curb_outer = half_road + farm_generator.CURB_WIDTH
    return {
        'ground': farm_generator.ground_mesh(),
        'road': farm_generator.ribbon(
            segments, -half_road, half_road, 0.01,
            farm_generator.METERS_PER_ROAD_TILE),
        'curb_top': farm_generator.ribbon(
            segments, half_road, curb_outer, farm_generator.CURB_HEIGHT,
            farm_generator.METERS_PER_CURB_TILE),
        'sidewalk': farm_generator.ribbon(
            segments, curb_outer, curb_outer + farm_generator.SIDEWALK_WIDTH,
            farm_generator.CURB_HEIGHT, farm_generator.METERS_PER_SIDEWALK_TILE),
        'track': farm_generator.straight_ribbon(
            0.0, 5.0, 5.0 + farm_generator.TRACK_LENGTH,
            farm_generator.TRACK_WIDTH, farm_generator.METERS_PER_TRACK_TILE),
    }


def textured_surfaces(farm_generator):
    """Everything the texture pass touches, including the vertical curb face and
    the raised bed, which are not walkable."""
    segments = farm_generator.centerline_frames(farm_generator.road_centerline())
    return walkable_surfaces(farm_generator) | {
        'curb_face': farm_generator.curb_face(
            segments, farm_generator.ROAD_WIDTH / 2.0,
            farm_generator.METERS_PER_CURB_TILE),
        'bed': farm_generator.bed_mesh(0.0),
    }


def test_walkable_surfaces_face_upward(farm_generator):
    for name, mesh in walkable_surfaces(farm_generator).items():
        assert upward_triangle_count(mesh) == len(mesh.triangles), name


def test_the_committed_world_matches_its_generator(farm_generator):
    """worlds/farm.sdf is generated output; nothing else keeps the two in step."""
    committed = open(
        os.path.join(SIMULATION_DIR, 'worlds', 'farm.sdf')).read()
    assert farm_generator.world_sdf() == committed, (
        'worlds/farm.sdf is stale — rerun farm_generator.py')


def test_every_referenced_asset_resolves(farm_generator):
    """A path gz cannot open renders the surface black without an error."""
    world = open(os.path.join(SIMULATION_DIR, 'worlds', 'farm.sdf')).read()
    references = re.findall(
        r'<(?:uri|albedo_map|normal_map|roughness_map)>(model://[^<]+)<', world)
    assert references
    for reference in set(references):
        path = os.path.join(
            SIMULATION_DIR, 'models', reference[len('model://'):])
        assert os.path.exists(path), reference


def texture_stretch(mesh):
    """Widest ratio between metres-per-UV-unit along a quad and across it."""
    worst = 1.0
    for base in range(0, len(mesh.positions), 4):
        corners = mesh.positions[base:base + 4]
        uvs = mesh.uvs[base:base + 4]
        for first, second, third in ((0, 1, 3), (2, 3, 1)):
            along = math.dist(corners[first], corners[second])
            across = math.dist(corners[first], corners[third])
            along_uv = math.dist(uvs[first], uvs[second])
            across_uv = math.dist(uvs[first], uvs[third])
            if min(along_uv, across_uv) < 1e-9:
                continue
            ratio = (along / along_uv) / (across / across_uv)
            worst = max(worst, ratio, 1.0 / ratio)
    return worst


def test_textures_are_applied_without_stretching(farm_generator):
    for name, mesh in textured_surfaces(farm_generator).items():
        assert texture_stretch(mesh) == pytest.approx(1.0, abs=0.01), name


def test_launch_spawn_pose_matches_the_generated_field(farm_generator, launch_constants):
    generated_x, generated_y, _, generated_yaw = farm_generator.field_spawn_pose()
    configured = launch_constants['NAMED_SPAWN_POSES']['farm']['taro']
    assert configured['x'] == pytest.approx(generated_x, abs=SPAWN_TOLERANCE_M)
    assert configured['y'] == pytest.approx(generated_y, abs=SPAWN_TOLERANCE_M)
    assert configured['yaw'] == pytest.approx(generated_yaw, abs=0.02)
