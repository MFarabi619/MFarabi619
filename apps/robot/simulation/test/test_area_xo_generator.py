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
import json
import os
import xml.etree.ElementTree as ElementTree

import pytest
from shapely import minimum_clearance, Point, Polygon

SIMULATION_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
WORLD_PATH = os.path.join(SIMULATION_DIRECTORY, 'worlds', 'area_xo.sdf')
LAUNCH_PATH = os.path.join(SIMULATION_DIRECTORY, 'launch', 'simulation.launch.py')
TARGET_PATH = os.path.join(SIMULATION_DIRECTORY, 'src', 'target.py')
AREA_XO_BUILDING_CENTROID_TOLERANCE_METERS = 3.0
HEIGHT_TOLERANCE_METERS = 1e-3
SPAWN_POSITION_TOLERANCE_METERS = 1e-3
GAZEBO_POLYLINE_TOLERANCE_METERS = 1e-4

pytestmark = pytest.mark.skipif(
    not os.path.exists(WORLD_PATH),
    reason='generate the world first: pixi r -m apps/robot generate-world area_xo')


@pytest.fixture(scope='module')
def area_xo_generator():
    spec = importlib.util.spec_from_file_location(
        'area_xo_generator', os.path.join(SIMULATION_DIRECTORY, 'area_xo_generator.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='module')
def world():
    return ElementTree.parse(WORLD_PATH).getroot().find('world')


def area_xo_entry(path, table_name):
    module = ast.parse(open(path).read())
    for statement in module.body:
        if (isinstance(statement, ast.Assign)
                and getattr(statement.targets[0], 'id', None) == table_name):
            return ast.literal_eval(statement.value)['area_xo']
    raise AssertionError(f'{table_name} not found in {path}')


@pytest.fixture(scope='module')
def spawn_pose():
    return area_xo_entry(LAUNCH_PATH, 'WORLD_SPAWN_POSES')


def vector(element, tag):
    return [float(value) for value in element.find(tag).text.split()]


def heightmaps(world):
    return world.findall("model[@name='terrain']/link/*/geometry/heightmap")


def terrain_offset(world):
    return vector(world.find("model[@name='terrain']/link/collision"), 'pose')[:3]


def gdalinfo(area_xo_generator, path):
    return json.loads(area_xo_generator.run('gdalinfo', '-json', '-mm', path))


def building_polygons(world):
    return [
        Polygon(rings[0], rings[1:]) for rings in (
            [[tuple(map(float, point.text.split())) for point in polyline.findall('point')]
             for polyline in visual.findall('geometry/polyline')]
            for visual in world.findall("model[@name='buildings']/link/visual"))]


def test_world_reports_gps_from_the_area_xo_building(area_xo_generator, world):
    spherical_coordinates = world.find('spherical_coordinates')
    assert world.find("plugin[@filename='gz-sim-navsat-system']") is not None
    assert (float(spherical_coordinates.find('latitude_deg').text)
            == area_xo_generator.ORIGIN_LATITUDE_DEGREES)
    assert (float(spherical_coordinates.find('longitude_deg').text)
            == area_xo_generator.ORIGIN_LONGITUDE_DEGREES)
    assert float(spherical_coordinates.find('heading_deg').text) == 0.0


def test_visual_and_collision_share_one_heightmap(world):
    collision, visual = heightmaps(world)
    for tag in ('uri', 'size'):
        assert collision.find(tag).text.strip() == visual.find(tag).text.strip()
    assert collision.find('pos') is None
    assert vector(visual, 'pos') == terrain_offset(world)


def test_heightmap_is_square_with_a_power_of_two_plus_one_samples(area_xo_generator):
    columns, rows = gdalinfo(area_xo_generator, area_xo_generator.HEIGHTMAP_PATH)['size']
    assert columns == rows == area_xo_generator.HEIGHTMAP_INTERVALS + 1
    assert (columns - 1).bit_count() == 1


def test_heightmap_samples_span_the_terrain_size(area_xo_generator, world):
    heightmap_raster = gdalinfo(area_xo_generator, area_xo_generator.HEIGHTMAP_PATH)
    resolution_meters = heightmap_raster['geoTransform'][1]
    size = vector(heightmaps(world)[0], 'size')
    assert size[0] == size[1] == area_xo_generator.TERRAIN_SIZE_METERS
    assert resolution_meters * (heightmap_raster['size'][0] - 1) == pytest.approx(
        area_xo_generator.TERRAIN_SIZE_METERS)


def test_vertical_size_matches_the_height_range_so_physics_is_unscaled(area_xo_generator, world):
    band = gdalinfo(area_xo_generator, area_xo_generator.HEIGHTMAP_PATH)['bands'][0]
    size = vector(heightmaps(world)[0], 'size')
    assert size[2] == pytest.approx(band['computedMax'] - band['computedMin'],
                                    abs=HEIGHT_TOLERANCE_METERS)


def test_imagery_is_one_texture_stretched_over_the_whole_terrain(area_xo_generator, world):
    [texture] = heightmaps(world)[1].findall('texture')
    assert float(texture.find('size').text) == area_xo_generator.TERRAIN_SIZE_METERS
    assert (gdalinfo(area_xo_generator, area_xo_generator.TEXTURE_PATH)['size']
            == [area_xo_generator.TEXTURE_PIXELS] * 2)
    assert gdalinfo(area_xo_generator, area_xo_generator.NORMAL_MAP_PATH)['size'] == [1, 1]


def test_area_xo_building_ground_is_at_world_height_zero(area_xo_generator, world):
    offset = terrain_offset(world)
    ground_height = area_xo_generator.height_at(area_xo_generator.HEIGHTMAP_PATH, 0.0, 0.0)
    assert ground_height + offset[2] == pytest.approx(0.0, abs=HEIGHT_TOLERANCE_METERS)


def test_robots_spawn_at_the_gps_spawn_just_above_the_terrain(
        area_xo_generator, world, spawn_pose):
    offset = terrain_offset(world)
    spawn_east, spawn_north, spawn_height, spawn_yaw = area_xo_generator.spawn_pose(-offset[2])
    assert (spawn_pose['x'], spawn_pose['y']) == pytest.approx(
        (spawn_east, spawn_north), abs=SPAWN_POSITION_TOLERANCE_METERS)
    assert spawn_pose['yaw'] == spawn_yaw
    ground_height = area_xo_generator.height_at(
        area_xo_generator.HEIGHTMAP_PATH, spawn_pose['x'], spawn_pose['y'])
    assert spawn_pose['z'] - (ground_height + offset[2]) == pytest.approx(
        area_xo_generator.SPAWN_CLEARANCE_METERS, abs=HEIGHT_TOLERANCE_METERS)
    assert spawn_pose['z'] == pytest.approx(spawn_height, abs=HEIGHT_TOLERANCE_METERS)


def test_target_stands_on_the_terrain(area_xo_generator, world):
    target_pose = area_xo_entry(TARGET_PATH, 'TARGET_SPAWN_POSES')
    ground_height = area_xo_generator.height_at(
        area_xo_generator.HEIGHTMAP_PATH, target_pose['x'], target_pose['y'])
    assert target_pose['z'] == pytest.approx(ground_height + terrain_offset(world)[2],
                                             abs=HEIGHT_TOLERANCE_METERS)


def test_area_xo_building_sits_at_the_world_origin(world):
    origin = Point(0.0, 0.0)
    assert min(origin.distance(polygon.centroid) for polygon in building_polygons(world)) < (
        AREA_XO_BUILDING_CENTROID_TOLERANCE_METERS)


def test_buildings_are_valid_polygons_with_their_holes_in_place(world):
    invalid_buildings = [polygon for polygon in building_polygons(world) if not polygon.is_valid]
    assert not invalid_buildings


def test_building_vertices_stay_further_apart_than_gazebo_merges(world):
    smallest_clearance_meters = min(
        minimum_clearance(polygon) for polygon in building_polygons(world))
    assert smallest_clearance_meters > GAZEBO_POLYLINE_TOLERANCE_METERS
