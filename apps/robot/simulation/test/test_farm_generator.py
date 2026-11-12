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

SIMULATION_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LAUNCH_DIRECTORY = os.path.join(SIMULATION_DIRECTORY, 'launch')
SPAWN_TOLERANCE_METERS = 0.05


@pytest.fixture(scope='module')
def farm_generator():
    path = os.path.join(SIMULATION_DIRECTORY, 'farm_generator.py')
    if SIMULATION_DIRECTORY not in sys.path:
        sys.path.insert(0, SIMULATION_DIRECTORY)
    spec = importlib.util.spec_from_file_location('farm_generator', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='module')
def launch_constants():
    source = ast.parse(open(os.path.join(LAUNCH_DIRECTORY, 'simulation.launch.py')).read())
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
    half_road = farm_generator.ROAD_WIDTH_METERS / 2.0
    curb_outer = half_road + farm_generator.CURB_WIDTH_METERS
    return {
        'ground': farm_generator.ground_mesh(),
        'road': farm_generator.ribbon(
            segments, -half_road, half_road, farm_generator.ROAD_SURFACE_HEIGHT_METERS,
            farm_generator.METERS_PER_ROAD_TEXTURE_TILE),
        'curb_top': farm_generator.ribbon(
            segments, half_road, curb_outer, farm_generator.CURB_HEIGHT_METERS,
            farm_generator.METERS_PER_CURB_TEXTURE_TILE),
        'sidewalk': farm_generator.ribbon(
            segments, curb_outer, curb_outer + farm_generator.SIDEWALK_WIDTH_METERS,
            farm_generator.CURB_HEIGHT_METERS, farm_generator.METERS_PER_SIDEWALK_TEXTURE_TILE),
        'track': farm_generator.straight_ribbon(
            0.0, 5.0, 5.0 + farm_generator.TRACK_LENGTH_METERS,
            farm_generator.TRACK_WIDTH_METERS, farm_generator.METERS_PER_TRACK_TEXTURE_TILE),
    }


def textured_surfaces(farm_generator):
    """Everything the texture pass touches, including the vertical curb face and
    the raised bed, which are not walkable."""
    segments = farm_generator.centerline_frames(farm_generator.road_centerline())
    return walkable_surfaces(farm_generator) | {
        'curb_face': farm_generator.curb_face(
            segments, farm_generator.ROAD_WIDTH_METERS / 2.0, 1.0,
            farm_generator.METERS_PER_CURB_TEXTURE_TILE),
        'bed': farm_generator.bed_mesh(0.0),
    }


def test_walkable_surfaces_face_upward(farm_generator):
    for name, mesh in walkable_surfaces(farm_generator).items():
        assert upward_triangle_count(mesh) == len(mesh.triangles), name


def test_the_committed_world_matches_its_generator(farm_generator):
    """worlds/farm.sdf is generated output; nothing else keeps the two in step."""
    committed = open(
        os.path.join(SIMULATION_DIRECTORY, 'worlds', 'farm.sdf')).read()
    assert farm_generator.world_sdf() == committed, (
        'worlds/farm.sdf is stale — rerun farm_generator.py')


def test_every_referenced_asset_resolves(farm_generator):
    """A path gz cannot open renders the surface black without an error."""
    world = open(os.path.join(SIMULATION_DIRECTORY, 'worlds', 'farm.sdf')).read()
    references = re.findall(
        r'<(?:uri|albedo_map|normal_map|roughness_map)>(model://[^<]+)<', world)
    assert references
    for reference in set(references):
        path = os.path.join(
            SIMULATION_DIRECTORY, 'models', reference[len('model://'):])
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


@pytest.fixture(scope='module')
def target_spawn_poses():
    spec = importlib.util.spec_from_file_location(
        'target', os.path.join(SIMULATION_DIRECTORY, 'src', 'target.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.TARGET_SPAWN_POSES


def signed_distance_from_centerline(farm_generator, x, y):
    nearest_distance, nearest_side = math.inf, 1.0
    for start, end, normal, _, _ in farm_generator.centerline_frames(
            farm_generator.road_centerline()):
        along_x, along_y = end[0] - start[0], end[1] - start[1]
        fraction = ((x - start[0]) * along_x + (y - start[1]) * along_y) / (
            along_x * along_x + along_y * along_y)
        fraction = min(1.0, max(0.0, fraction))
        offset_x = x - (start[0] + fraction * along_x)
        offset_y = y - (start[1] + fraction * along_y)
        distance = math.hypot(offset_x, offset_y)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_side = 1.0 if offset_x * normal[0] + offset_y * normal[1] >= 0.0 else -1.0
    return nearest_side * nearest_distance


def test_curb_faces_face_the_road_on_both_sides(farm_generator):
    segments = farm_generator.centerline_frames(farm_generator.road_centerline())
    half_road = farm_generator.ROAD_WIDTH_METERS / 2.0
    for side in (1.0, -1.0):
        mesh = farm_generator.curb_face(
            segments, half_road * side, side, farm_generator.METERS_PER_CURB_TEXTURE_TILE)
        for quad, (start, _, _, _, _) in enumerate(segments):
            corner = mesh.positions[quad * 4]
            face_normal = mesh.normals[quad * 4]
            toward_road = (start[0] - corner[0], start[1] - corner[1])
            assert face_normal[0] * toward_road[0] + face_normal[1] * toward_road[1] > 0.0, side


def test_parked_cars_stay_inside_the_road(farm_generator):
    frames = farm_generator.centerline_frames(farm_generator.road_centerline())
    half_widths = [half_width for _, _, half_width in farm_generator.CAR_MODELS]
    for (uri, x, y, _), half_width in zip(farm_generator.car_placements(frames), half_widths):
        outer_edge = abs(signed_distance_from_centerline(farm_generator, x, y)) + half_width
        assert outer_edge <= farm_generator.ROAD_WIDTH_METERS / 2.0, uri


def test_the_farm_person_stands_on_the_sidewalk(farm_generator, target_spawn_poses):
    pose = target_spawn_poses['farm']
    curb_outer = farm_generator.ROAD_WIDTH_METERS / 2.0 + farm_generator.CURB_WIDTH_METERS
    sidewalk_outer = curb_outer + farm_generator.SIDEWALK_WIDTH_METERS
    distance = abs(signed_distance_from_centerline(farm_generator, pose['x'], pose['y']))
    assert curb_outer < distance < sidewalk_outer
    assert pose['z'] == pytest.approx(farm_generator.CURB_HEIGHT_METERS)


def test_launch_spawn_pose_matches_the_generated_field(farm_generator, launch_constants):
    generated_x, generated_y, _, generated_yaw = farm_generator.field_spawn_pose()
    configured = launch_constants['NAMED_SPAWN_POSES']['farm']['taro']
    assert configured['x'] == pytest.approx(generated_x, abs=SPAWN_TOLERANCE_METERS)
    assert configured['y'] == pytest.approx(generated_y, abs=SPAWN_TOLERANCE_METERS)
    assert configured['yaw'] == pytest.approx(generated_yaw, abs=0.02)
