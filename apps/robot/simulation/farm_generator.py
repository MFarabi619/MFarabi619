#!/usr/bin/env python3

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
import os
from typing import NamedTuple
import xml.etree.ElementTree as ElementTree

import collada_mesh
import cv2
import numpy as np

SIMULATOR_DIR = os.path.dirname(os.path.abspath(__file__))
MESH_DIR = os.path.join(SIMULATOR_DIR, 'models', 'materials')
TEXTURE_DIR = os.path.join(MESH_DIR, 'textures')
WORLD_PATH = os.path.join(SIMULATOR_DIR, 'worlds', 'farm.sdf')

SITE_HALF_LENGTH = 60.0
SITE_HALF_WIDTH = 45.0

ROAD_WIDTH = 5.4
ROAD_CURVE_AMPLITUDE = 6.0
ROAD_CURVE_CYCLES = 0.75
ROAD_SEGMENTS = 160

CURB_WIDTH = 0.16
CURB_HEIGHT = 0.13
SIDEWALK_WIDTH = 1.7
VERGE_WIDTH = 1.1

TRACK_WIDTH = 2.6
TRACK_LENGTH = 34.0
TRACK_STATIONS = (0.22, 0.52, 0.82)

METERS_PER_ROAD_TILE = 2.5
METERS_PER_SIDEWALK_TILE = SIDEWALK_WIDTH / 2.0
METERS_PER_CURB_TILE = 0.5
METERS_PER_TRACK_TILE = 2.0
METERS_PER_GRASS_TILE = 3.0
METERS_PER_MULCH_TILE = 1.6

SIDEWALK_LABEL = 12
ROAD_LABEL = 13
GRASS_LABEL = 14

TEXTURE_TILES = (
    ('sidewalk_tile', 'sidewalk_color.jpg', (308, 63, 569, 315), 256, False, False),
    ('road_tile', 'road_color.jpg', (200, 200, 760, 760), 512, True, False),
    ('dirt_path_tile', 'dirt_path_color.jpg', (220, 220, 820, 820), 512, True, False),
    ('curb_tile', 'curb_color.jpg', (648, 72, 1024, 448), 256, True, False),
    ('mulch_tile', 'landscape_fabric.jpg', (60, 230, 830, 1000), 1024, True, True),
)
SEAM_BAND_PIXELS = 8
SEAM_INPAINT_RADIUS = 4

FLATTEN_SIGMA_FRACTION = 48.0

BED_LENGTH = 20.0
BED_PITCH = 1.2
BED_HEIGHT = 0.04
BED_COUNT = 10
BED_HALF_WIDTH = 0.32
BED_TOP_HALF_WIDTH = 0.18
BED_TEXTURE_PHASES = (0.0, 3.5)
PLANT_LINE_OFFSET = 0.1
FIELD_CENTER_X = 22.0
FIELD_CENTER_Y = 0.0
FIELD_MARGIN = 1.6
FIELD_APPROACH = 0.8

TURTLE_URI = 'https://fuel.gazebosim.org/1.0/JAMONCITO/models/turtle'
LOCAL_MODEL_PREFIX = 'model://'


class BedRow(NamedTuple):
    name: str
    uri: str
    spacing: float
    lines: int
    is_static: bool = False


BED_ROWS = (
    BedRow('pepper', 'model://pepper_plant', 0.6, 1),
    BedRow('potato', 'model://potato_plant', 0.5, 2),
    BedRow('onion', 'model://onion_plant', 0.35, 2),
    BedRow('carrot', 'model://carrot_plant', 0.35, 2),
    BedRow('pumpkin', 'model://pumpkin_plant', 0.9, 1),
    BedRow('maize_early', 'model://maize_01', 0.45, 2),
    BedRow('maize_late', 'model://maize_02', 0.45, 2),
    BedRow('turtle', TURTLE_URI, 0.8, 1, True),
    BedRow('pepper_late', 'model://pepper_plant', 0.6, 2),
    BedRow('potato_late', 'model://potato_plant', 0.5, 2),
)


WEED_URIS = ('model://nettle', 'model://unknown_weed')
WEED_HEIGHT_M = 0.32
WEED_COUNT = 60
PLANT_JITTER_M = 0.04
JITTER_SEED = 20260826

TREE_SPACING = 11.0
TREE_VERGE_OFFSET = 5.2
TREE_FIELD_CLEARANCE = 3.0
HOUSE_KEEP_CLEAR_M = 9.0
CAR_KEEP_CLEAR_M = 4.5
SPAWN_KEEP_CLEAR_M = 4.0

COTTAGE_URI = 'https://fuel.gazebosim.org/1.0/hisuki/models/house'
ROADSIDE_HOUSES = (
    (COTTAGE_URI, 0.62, 8.5),
)
SIDEWALK_SPAWN_STATION = 0.52

CAR_URIS = (
    'https://fuel.gazebosim.org/1.0/OpenRobotics/models/Prius Hybrid with sensors',
    'https://fuel.gazebosim.org/1.0/OpenRoboticsTest/models/Hatchback copy',
    'https://fuel.gazebosim.org/1.0/OpenRobotics/models/SUV',
)
CAR_STATIONS = (0.14, 0.40, 0.68)
CAR_HALF_WIDTH = 1.0

def seamless(image):
    height, width = image.shape[:2]
    rolled = np.roll(image, (height // 2, width // 2), axis=(0, 1))
    mask = np.zeros((height, width), np.uint8)
    half_band = SEAM_BAND_PIXELS // 2
    mask[height // 2 - half_band:height // 2 + half_band, :] = 255
    mask[:, width // 2 - half_band:width // 2 + half_band] = 255
    return cv2.inpaint(rolled, mask, SEAM_INPAINT_RADIUS, cv2.INPAINT_TELEA)


def flattened(image):
    blurred = cv2.GaussianBlur(
        image, (0, 0), min(image.shape[:2]) / FLATTEN_SIGMA_FRACTION)
    ratio = image.astype(np.float32) / np.maximum(blurred.astype(np.float32), 1.0)
    return np.clip(ratio * float(image.mean()), 0.0, 255.0).astype(np.uint8)


def write_texture_tiles():
    for name, source, crop, size, heal_seams, flatten in TEXTURE_TILES:
        photograph = cv2.imread(os.path.join(TEXTURE_DIR, source))
        if photograph is None:
            raise RuntimeError(f'missing texture source {source}')
        left, top, right, bottom = crop
        tile = cv2.resize(
            photograph[top:bottom, left:right], (size, size), interpolation=cv2.INTER_AREA)
        if flatten:
            tile = flattened(tile)
        if heal_seams:
            tile = seamless(tile)
        cv2.imwrite(
            os.path.join(TEXTURE_DIR, f'{name}.jpg'), tile,
            [cv2.IMWRITE_JPEG_QUALITY, 92])


def road_centerline():
    points = []
    for step in range(ROAD_SEGMENTS + 1):
        fraction = step / ROAD_SEGMENTS
        y = -SITE_HALF_LENGTH + 2.0 * SITE_HALF_LENGTH * fraction
        x = ROAD_CURVE_AMPLITUDE * math.sin(2.0 * math.pi * ROAD_CURVE_CYCLES * fraction)
        points.append((x, y))
    return points


def centerline_frames(points):
    frames = []
    travelled = 0.0
    for index in range(len(points) - 1):
        (start_x, start_y), (end_x, end_y) = points[index], points[index + 1]
        length = math.hypot(end_x - start_x, end_y - start_y)
        direction = ((end_x - start_x) / length, (end_y - start_y) / length)
        normal = (-direction[1], direction[0])
        frames.append(((start_x, start_y), (end_x, end_y), normal, travelled, travelled + length))
        travelled += length
    return frames


def ribbon(frames, inner_offset, outer_offset, height, meters_per_tile):
    mesh = collada_mesh.TexturedMesh()
    across_tiles = abs(outer_offset - inner_offset) / meters_per_tile
    for start, end, normal, start_distance, end_distance in frames:
        inner_start = (start[0] + normal[0] * inner_offset, start[1] + normal[1] * inner_offset)
        outer_start = (start[0] + normal[0] * outer_offset, start[1] + normal[1] * outer_offset)
        inner_end = (end[0] + normal[0] * inner_offset, end[1] + normal[1] * inner_offset)
        outer_end = (end[0] + normal[0] * outer_offset, end[1] + normal[1] * outer_offset)
        start_tile = start_distance / meters_per_tile
        end_tile = end_distance / meters_per_tile
        mesh.quad(
            [(inner_start[0], inner_start[1], height), (outer_start[0], outer_start[1], height),
             (outer_end[0], outer_end[1], height), (inner_end[0], inner_end[1], height)],
            (0.0, 0.0, 1.0),
            [(start_tile, 0.0), (start_tile, across_tiles),
             (end_tile, across_tiles), (end_tile, 0.0)])
    return mesh


def curb_face(frames, offset, meters_per_tile):
    mesh = collada_mesh.TexturedMesh()
    across_tiles = CURB_HEIGHT / meters_per_tile
    for start, end, normal, start_distance, end_distance in frames:
        face_start = (start[0] + normal[0] * offset, start[1] + normal[1] * offset)
        face_end = (end[0] + normal[0] * offset, end[1] + normal[1] * offset)
        start_tile = start_distance / meters_per_tile
        end_tile = end_distance / meters_per_tile
        mesh.quad(
            [(face_start[0], face_start[1], 0.0), (face_start[0], face_start[1], CURB_HEIGHT),
             (face_end[0], face_end[1], CURB_HEIGHT), (face_end[0], face_end[1], 0.0)],
            (-normal[0], -normal[1], 0.0),
            [(start_tile, 0.0), (start_tile, across_tiles),
             (end_tile, across_tiles), (end_tile, 0.0)])
    return mesh


def straight_ribbon(center_y, start_x, end_x, width, meters_per_tile):
    mesh = collada_mesh.TexturedMesh()
    along_tiles = abs(end_x - start_x) / meters_per_tile
    across_tiles = width / meters_per_tile
    half = width / 2.0
    mesh.quad(
        [(start_x, center_y - half, 0.005), (start_x, center_y + half, 0.005),
         (end_x, center_y + half, 0.005), (end_x, center_y - half, 0.005)],
        (0.0, 0.0, 1.0),
        [(0.0, 0.0), (0.0, across_tiles), (along_tiles, across_tiles), (along_tiles, 0.0)])
    return mesh


def rectangle_mesh(half_length_x, half_length_y, meters_per_tile):
    mesh = collada_mesh.TexturedMesh()
    tiles_x = 2.0 * half_length_x / meters_per_tile
    tiles_y = 2.0 * half_length_y / meters_per_tile
    mesh.quad(
        [(-half_length_x, -half_length_y, 0.0), (-half_length_x, half_length_y, 0.0),
         (half_length_x, half_length_y, 0.0), (half_length_x, -half_length_y, 0.0)],
        (0.0, 0.0, 1.0),
        [(0.0, 0.0), (0.0, tiles_y), (tiles_x, tiles_y), (tiles_x, 0.0)])
    return mesh


def ground_mesh():
    return rectangle_mesh(SITE_HALF_WIDTH, SITE_HALF_LENGTH, METERS_PER_GRASS_TILE)


def bed_mesh(texture_phase):
    half_length = BED_LENGTH / 2.0
    slope_run = BED_HALF_WIDTH - BED_TOP_HALF_WIDTH
    slope_length = math.hypot(slope_run, BED_HEIGHT)
    slope_normal = (BED_HEIGHT / slope_length, slope_run / slope_length)

    along = BED_LENGTH / METERS_PER_MULCH_TILE
    slope_tiles = slope_length / METERS_PER_MULCH_TILE
    top_tiles = 2.0 * BED_TOP_HALF_WIDTH / METERS_PER_MULCH_TILE

    def band(lower, upper):
        return [(texture_phase, lower), (texture_phase + along, lower),
                (texture_phase + along, upper), (texture_phase, upper)]

    mesh = collada_mesh.TexturedMesh()
    mesh.quad(
        [(-half_length, -BED_HALF_WIDTH, 0.0), (half_length, -BED_HALF_WIDTH, 0.0),
         (half_length, -BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (-half_length, -BED_TOP_HALF_WIDTH, BED_HEIGHT)],
        (0.0, -slope_normal[0], slope_normal[1]),
        band(0.0, slope_tiles))
    mesh.quad(
        [(-half_length, -BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half_length, -BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half_length, BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (-half_length, BED_TOP_HALF_WIDTH, BED_HEIGHT)],
        (0.0, 0.0, 1.0),
        band(slope_tiles, slope_tiles + top_tiles))
    mesh.quad(
        [(-half_length, BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half_length, BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half_length, BED_HALF_WIDTH, 0.0), (-half_length, BED_HALF_WIDTH, 0.0)],
        (0.0, slope_normal[0], slope_normal[1]),
        band(slope_tiles + top_tiles, 2.0 * slope_tiles + top_tiles))
    for sign in (-1.0, 1.0):
        end_x = sign * half_length
        profile = ((-BED_HALF_WIDTH, 0.0), (-BED_TOP_HALF_WIDTH, BED_HEIGHT),
                   (BED_TOP_HALF_WIDTH, BED_HEIGHT), (BED_HALF_WIDTH, 0.0))
        mesh.quad(
            [(end_x, y, z) for y, z in profile],
            (sign, 0.0, 0.0),
            [(y / METERS_PER_MULCH_TILE, z / METERS_PER_MULCH_TILE) for y, z in profile])
    return mesh


def write_mesh(name, mesh, texture):
    path = os.path.join(MESH_DIR, f'{name}.dae')
    with open(path, 'w') as mesh_file:
        mesh_file.write(collada_mesh.document(
            name, mesh.positions, mesh.normals, mesh.triangles,
            texture=texture, uvs=mesh.uvs))
    return len(mesh.triangles)


def static_visual(name, mesh_name, label=None):
    label_plugin = (
        f'''
      <plugin filename="gz-sim-label-system" name="gz::sim::systems::Label">
        <label>{label}</label>
      </plugin>''' if label is not None else '')
    return f'''
    <model name="{name}">
      <static>true</static>
      <link name="link">
        <visual name="visual">
          <geometry>
            <mesh><uri>model://materials/{mesh_name}.dae</uri></mesh>
          </geometry>
        </visual>
        <collision name="collision">
          <geometry>
            <mesh><uri>model://materials/{mesh_name}.dae</uri></mesh>
          </geometry>
        </collision>
      </link>{label_plugin}
    </model>'''


def mulch_beds():
    models = []
    for index in range(BED_COUNT):
        bed_y = FIELD_CENTER_Y + (index - (BED_COUNT - 1) / 2.0) * BED_PITCH
        variant = 'a' if index % 2 == 0 else 'b'
        models.append(f'''
    <model name="bed_{index}">
      <static>true</static>
      <pose>{FIELD_CENTER_X:.3f} {bed_y:.3f} 0 0 0 0</pose>
      <link name="link">
        <visual name="visual">
          <geometry>
            <mesh><uri>model://materials/farm_bed_{variant}.dae</uri></mesh>
          </geometry>
        </visual>
        <collision name="collision">
          <geometry>
            <mesh><uri>model://materials/farm_bed_{variant}.dae</uri></mesh>
          </geometry>
        </collision>
      </link>
    </model>''')
    return models


jitter_rng = np.random.default_rng(JITTER_SEED)


def scattered(value):
    return value + jitter_rng.uniform(-PLANT_JITTER_M, PLANT_JITTER_M)


def plant_placements():
    global jitter_rng
    jitter_rng = np.random.default_rng(JITTER_SEED)
    placements = bed_plants()
    for uri, entries in field_weeds().items():
        placements.setdefault(uri, []).extend(entries)
    return placements


def planted_field():
    models = []
    for uri, entries in plant_placements().items():
        if uri.startswith(LOCAL_MODEL_PREFIX):
            models.append(baked_visual(uri[len(LOCAL_MODEL_PREFIX):]))
        else:
            models.extend(scattered_includes(uri, entries))
    return models


def model_scale(name):
    root = ElementTree.parse(
        os.path.join(SIMULATOR_DIR, 'models', name, 'model.sdf')).getroot()
    scale = next(root.iter('scale'), None)
    return 1.0 if scale is None else float(scale.text.split()[0])


def plant_scale(name, source):
    if uri_of(name) not in WEED_URIS:
        return model_scale(name)
    height = max(position[2] for position in source.positions) - min(
        position[2] for position in source.positions)
    return WEED_HEIGHT_M / height


def uri_of(name):
    return f'{LOCAL_MODEL_PREFIX}{name}'


def write_plant_meshes(counts):
    for uri, entries in plant_placements().items():
        if not uri.startswith(LOCAL_MODEL_PREFIX):
            continue
        name = uri[len(LOCAL_MODEL_PREFIX):]
        source = collada_mesh.read_mesh(os.path.join(
            SIMULATOR_DIR, 'models', name, 'meshes', f'{name}.dae'))
        counts[name] = write_baked_mesh(name, collada_mesh.replicated(
            source, entries, plant_scale(name, source)))


def scattered_includes(uri, placements):
    return [f'''
    <include>
      <name>scatter_{index}</name>
      <static>true</static>
      <pose>{x:.3f} {y:.3f} {z} 0 0 {yaw:g}</pose>
      <uri>{uri}</uri>
    </include>''' for index, (x, y, z, yaw) in enumerate(placements)]


def write_baked_mesh(name, mesh):
    texture = (f'../{name}/materials/textures/{os.path.basename(mesh.texture)}'
               if mesh.texture else None)
    with open(os.path.join(MESH_DIR, f'farm_{name}.dae'), 'w') as mesh_file:
        mesh_file.write(collada_mesh.document(
            f'farm_{name}', mesh.positions, mesh.normals, mesh.triangles,
            texture=texture, uvs=mesh.uvs or None,
            color=None if texture else mesh.color))
    return len(mesh.triangles)


def baked_visual(name):
    return f'''
    <model name="{name}_field">
      <static>true</static>
      <link name="link">
        <visual name="visual">
          <cast_shadows>false</cast_shadows>
          <geometry>
            <mesh><uri>model://materials/farm_{name}.dae</uri></mesh>
          </geometry>
        </visual>
      </link>
    </model>'''


def bed_plants():
    placements = {}
    for index in range(BED_COUNT):
        bed_y = FIELD_CENTER_Y + (index - (BED_COUNT - 1) / 2.0) * BED_PITCH
        row = BED_ROWS[index % len(BED_ROWS)]
        plant_count = int(BED_LENGTH / row.spacing)
        for line in range(row.lines):
            line_y = bed_y + (line - (row.lines - 1) / 2.0) * 2.0 * PLANT_LINE_OFFSET
            for plant in range(plant_count):
                plant_x = FIELD_CENTER_X + (
                    plant - (plant_count - 1) / 2.0) * row.spacing
                yaw = (index * 131 + line * 37 + plant * 17) % 63 / 10.0
                placements.setdefault(row.uri, []).append(
                    (scattered(plant_x), scattered(line_y), BED_HEIGHT, yaw))
    return placements




def field_weeds():
    half_span = bed_half_span()
    placements = {}
    for index in range(WEED_COUNT):
        aisle = (index % (BED_COUNT - 1)) - (BED_COUNT - 2) / 2.0
        weed_y = FIELD_CENTER_Y + aisle * BED_PITCH + BED_PITCH / 2.0
        weed_x = FIELD_CENTER_X + (
            (index * 7 % BED_LENGTH) - BED_LENGTH / 2.0)
        if abs(weed_y - FIELD_CENTER_Y) > half_span:
            continue
        placements.setdefault(WEED_URIS[index % len(WEED_URIS)], []).append(
            (scattered(weed_x), scattered(weed_y), 0.0,
             (index * 29) % 63 / 10.0))
    return placements


def bed_half_span():
    return (BED_COUNT - 1) / 2.0 * BED_PITCH + BED_HALF_WIDTH


def field_extents():
    lowest_y = FIELD_CENTER_Y - bed_half_span() - FIELD_MARGIN
    highest_y = FIELD_CENTER_Y + bed_half_span() + FIELD_MARGIN
    return (BED_LENGTH / 2.0 + FIELD_MARGIN, (highest_y - lowest_y) / 2.0,
            (highest_y + lowest_y) / 2.0)


def field_dirt():
    _, _, center_y = field_extents()
    return f'''
    <model name="field_dirt">
      <static>true</static>
      <pose>{FIELD_CENTER_X:.3f} {center_y:.3f} 0.002 0 0 0</pose>
      <link name="link">
        <visual name="visual">
          <geometry>
            <mesh><uri>model://materials/farm_field_dirt.dae</uri></mesh>
          </geometry>
        </visual>
      </link>
    </model>'''


def field_side_edge_x(frames, target_y, offset):
    """Where the road's field-side edge sits at a given y. Projecting the offset
    onto x alone ignores the curve and starts the tracks on the tarmac."""
    if not frames:
        raise ValueError('field_side_edge_x needs at least one road segment')
    crossings = []
    nearest = (math.inf, 0.0)
    for start, end, normal, _, _ in frames:
        first = (start[0] - normal[0] * offset, start[1] - normal[1] * offset)
        second = (end[0] - normal[0] * offset, end[1] - normal[1] * offset)
        for point in (first, second):
            nearest = min(nearest, (abs(point[1] - target_y), point[0]))
        low, high = sorted((first[1], second[1]))
        if not low <= target_y <= high:
            continue
        span = second[1] - first[1]
        fraction = 0.0 if abs(span) < 1e-9 else (target_y - first[1]) / span
        crossings.append(first[0] + fraction * (second[0] - first[0]))
    if crossings:
        return max(crossings)
    return nearest[1]


def track_end_x(start_x, track_y):
    _, half_length_y, center_y = field_extents()
    crop_near_x = FIELD_CENTER_X - BED_LENGTH / 2.0
    abreast_of_field = center_y - half_length_y <= track_y <= center_y + half_length_y
    if abreast_of_field:
        return min(start_x + TRACK_LENGTH, crop_near_x)
    return start_x + TRACK_LENGTH


def obstructs_the_field(x, y):
    """The road curves to within a canopy's reach of the field, so a tree can
    land between the robot's start and the first row and hide the whole crop."""
    half_length_x, half_length_y, center_y = field_extents()
    approach_x = FIELD_CENTER_X - BED_LENGTH / 2.0 - FIELD_APPROACH
    return (approach_x - TREE_FIELD_CLEARANCE <= x
            <= FIELD_CENTER_X + half_length_x + TREE_FIELD_CLEARANCE
            and center_y - half_length_y - TREE_FIELD_CLEARANCE <= y
            <= center_y + half_length_y + TREE_FIELD_CLEARANCE)


def away_from_field(start, normal):
    return -1.0 if normal[0] * (FIELD_CENTER_X - start[0]) > 0.0 else 1.0


def house_placements(frames):
    for uri, station, verge_offset in ROADSIDE_HOUSES:
        start, _, normal, _, _ = frames[int(station * (len(frames) - 1))]
        side = -away_from_field(start, normal)
        yield (uri,
               start[0] + normal[0] * verge_offset * side,
               start[1] + normal[1] * verge_offset * side,
               math.atan2(-normal[1] * side, -normal[0] * side))


def car_placements(frames):
    for uri, station in zip(CAR_URIS, CAR_STATIONS):
        start, _, normal, _, _ = frames[int(station * (len(frames) - 1))]
        offset = (ROAD_WIDTH / 2.0 - CAR_HALF_WIDTH) * away_from_field(start, normal)
        yield (uri,
               start[0] + normal[0] * offset,
               start[1] + normal[1] * offset,
               math.atan2(-normal[0], normal[1]))


def roadside_houses(points):
    return [f'''
    <include>
      <name>house_{index}</name>
      <pose>{x:.3f} {y:.3f} 0 0 0 {heading:.3f}</pose>
      <uri>{uri}</uri>
    </include>'''
            for index, (uri, x, y, heading)
            in enumerate(house_placements(centerline_frames(points)))]


def roadside_cars(points):
    return [f'''
    <include>
      <name>car_{index}</name>
      <static>true</static>
      <pose>{x:.3f} {y:.3f} 0 0 0 {heading:.3f}</pose>
      <uri>{uri}</uri>
    </include>'''
            for index, (uri, x, y, heading)
            in enumerate(car_placements(centerline_frames(points)))]


def occupied_ground(frames):
    return ([(x, y, HOUSE_KEEP_CLEAR_M) for _, x, y, _ in house_placements(frames)]
            + [(x, y, CAR_KEEP_CLEAR_M) for _, x, y, _ in car_placements(frames)]
            + [(*sidewalk_spawn_pose()[:2], SPAWN_KEEP_CLEAR_M)])


def roadside_trees(points):
    entries = []
    distance_since_tree = TREE_SPACING
    frames = centerline_frames(points)
    reserved = occupied_ground(frames)
    for start, _, normal, start_distance, end_distance in frames:
        distance_since_tree += end_distance - start_distance
        if distance_since_tree < TREE_SPACING:
            continue
        distance_since_tree = 0.0
        side = -1.0 if len(entries) % 2 else 1.0
        offset = TREE_VERGE_OFFSET * side
        tree_x = start[0] + normal[0] * offset
        tree_y = start[1] + normal[1] * offset
        if obstructs_the_field(tree_x, tree_y):
            continue
        if any(math.hypot(tree_x - x, tree_y - y) < clearance
               for x, y, clearance in reserved):
            continue
        model = 'Oak tree' if len(entries) % 3 else 'Pine Tree'
        entries.append(f'''
    <include>
      <name>tree_{len(entries)}</name>
      <pose>{tree_x:.3f} {tree_y:.3f} 0 0 0 0</pose>
      <uri>https://fuel.gazebosim.org/1.0/OpenRobotics/models/{model}</uri>
      <plugin filename="gz-sim-label-system" name="gz::sim::systems::Label">
        <label>20</label>
      </plugin>
    </include>''')
    return entries


def field_spawn_pose():
    return (FIELD_CENTER_X - BED_LENGTH / 2.0 - FIELD_APPROACH,
            FIELD_CENTER_Y - BED_PITCH / 2.0, 0.4, 0.0)


def sidewalk_spawn_pose():
    frames = centerline_frames(road_centerline())
    start, _, normal, _, _ = frames[int(SIDEWALK_SPAWN_STATION * (len(frames) - 1))]
    offset = ROAD_WIDTH / 2.0 + CURB_WIDTH + SIDEWALK_WIDTH / 2.0
    forward_x, forward_y = normal[1], -normal[0]
    return (start[0] + normal[0] * offset, start[1] + normal[1] * offset,
            CURB_HEIGHT, math.atan2(forward_y, forward_x))


def build():
    points = road_centerline()
    frames = centerline_frames(points)
    half_road = ROAD_WIDTH / 2.0
    curb_outer = half_road + CURB_WIDTH
    sidewalk_outer = curb_outer + SIDEWALK_WIDTH

    write_texture_tiles()

    counts = {}
    counts['ground'] = write_mesh('farm_ground', ground_mesh(), 'textures/grass_color.jpg')
    counts['road'] = write_mesh(
        'farm_road', ribbon(frames, -half_road, half_road, 0.01, METERS_PER_ROAD_TILE),
        'textures/road_tile.jpg')
    for side_name, side in (('left', 1.0), ('right', -1.0)):
        counts[f'curb_top_{side_name}'] = write_mesh(
            f'farm_curb_top_{side_name}',
            ribbon(frames, half_road * side, curb_outer * side, CURB_HEIGHT,
                   METERS_PER_CURB_TILE),
            'textures/curb_tile.jpg')
        counts[f'curb_face_{side_name}'] = write_mesh(
            f'farm_curb_face_{side_name}',
            curb_face(frames, half_road * side, METERS_PER_CURB_TILE),
            'textures/curb_tile.jpg')
        counts[f'sidewalk_{side_name}'] = write_mesh(
            f'farm_sidewalk_{side_name}',
            ribbon(frames, curb_outer * side, sidewalk_outer * side, CURB_HEIGHT,
                   METERS_PER_SIDEWALK_TILE),
            'textures/sidewalk_tile.jpg')

    dirt_half_x, dirt_half_y, _ = field_extents()
    counts['field_dirt'] = write_mesh(
        'farm_field_dirt', rectangle_mesh(dirt_half_x, dirt_half_y, METERS_PER_TRACK_TILE),
        'textures/dirt_path_tile.jpg')
    for variant, phase in zip('ab', BED_TEXTURE_PHASES):
        counts[f'bed_{variant}'] = write_mesh(
            f'farm_bed_{variant}', bed_mesh(phase), 'textures/mulch_tile.jpg')

    for index, station in enumerate(TRACK_STATIONS):
        start = frames[int(station * (len(frames) - 1))][0]
        track_start_x = field_side_edge_x(frames, start[1], sidewalk_outer)
        counts[f'track_{index}'] = write_mesh(
            f'farm_track_{index}',
            straight_ribbon(start[1], track_start_x,
                            track_end_x(track_start_x, start[1]),
                            TRACK_WIDTH, METERS_PER_TRACK_TILE),
            'textures/dirt_path_tile.jpg')

    write_plant_meshes(counts)
    write_world()
    return counts, len(world_models())


def world_models():
    return [
        static_visual('farm_ground', 'farm_ground', GRASS_LABEL),
        static_visual('farm_road', 'farm_road', ROAD_LABEL),
    ] + [
        static_visual(f'farm_{surface}_{side}', f'farm_{surface}_{side}',
                      SIDEWALK_LABEL if surface == 'sidewalk' else None)
        for side in ('left', 'right')
        for surface in ('curb_face', 'curb_top', 'sidewalk')
    ] + [
        static_visual(f'farm_track_{index}', f'farm_track_{index}')
        for index in range(len(TRACK_STATIONS))
    ] + [field_dirt()] + mulch_beds() \
        + roadside_houses(road_centerline()) \
        + roadside_cars(road_centerline()) \
        + roadside_trees(road_centerline()) + planted_field()


def world_sdf():
    models = world_models()
    return f'''<?xml version="1.0" ?>
<sdf version="1.9">
  <world name="farm">
    <physics name="1ms" type="ignored">
      <max_step_size>0.001</max_step_size>
      <real_time_factor>1.0</real_time_factor>
    </physics>
    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"/>
    <plugin filename="gz-sim-scene-broadcaster-system"
            name="gz::sim::systems::SceneBroadcaster"/>
    <plugin filename="gz-sim-sensors-system" name="gz::sim::systems::Sensors">
      <render_engine>ogre2</render_engine>
      <background_color>0.6 0.75 0.9</background_color>
    </plugin>
    <plugin filename="gz-sim-imu-system" name="gz::sim::systems::Imu"/>
    <plugin filename="gz-sim-contact-system" name="gz::sim::systems::Contact"/>

    <spherical_coordinates>
      <surface_model>EARTH_WGS84</surface_model>
      <world_frame_orientation>ENU</world_frame_orientation>
      <latitude_deg>45.395134</latitude_deg>
      <longitude_deg>-75.572868</longitude_deg>
      <elevation>70.0</elevation>
      <heading_deg>0.0</heading_deg>
    </spherical_coordinates>

    <scene>
      <ambient>0.35 0.35 0.35 1</ambient>
      <background>0.7 0.8 0.9 1</background>
      <sky><clouds><speed>2</speed></clouds></sky>
      <grid>false</grid>
      <shadows>true</shadows>
      <fog>
        <type>linear</type>
        <color>0.78 0.84 0.90 1</color>
        <start>45</start>
        <end>140</end>
        <density>0.35</density>
      </fog>
    </scene>

    <light type="directional" name="sun">
      <cast_shadows>true</cast_shadows>
      <intensity>1.4</intensity>
      <pose>0 0 10 0 0 0</pose>
      <diffuse>0.85 0.85 0.85 1</diffuse>
      <specular>0.3 0.3 0.3 1</specular>
      <direction>-0.5 0.1 -0.9</direction>
    </light>
    <light type="directional" name="fill">
      <cast_shadows>false</cast_shadows>
      <pose>0 0 10 0 0 0</pose>
      <diffuse>0.35 0.35 0.35 1</diffuse>
      <specular>0 0 0 1</specular>
      <direction>0.5 -0.1 -0.9</direction>
    </light>

    <model name="ground_collision">
      <static>true</static>
      <link name="link">
        <collision name="collision">
          <geometry><plane><normal>0 0 1</normal>
            <size>{2 * SITE_HALF_WIDTH} {2 * SITE_HALF_LENGTH}</size></plane></geometry>
        </collision>
      </link>
    </model>
{''.join(models)}
  </world>
</sdf>
'''


def write_world():
    with open(WORLD_PATH, 'w') as world_file:
        world_file.write(world_sdf())


if __name__ == '__main__':
    triangle_counts, model_count = build()
    for name, triangles in triangle_counts.items():
        print(f'{name}: {triangles} triangles')
    print(f'{model_count} models -> {WORLD_PATH}')
    for label, pose in (('field', field_spawn_pose()), ('sidewalk', sidewalk_spawn_pose())):
        spawn_x, spawn_y, spawn_z, spawn_yaw = pose
        print(f'{label} spawn: x={spawn_x:.3f} y={spawn_y:.3f} z={spawn_z:.3f} '
              f'yaw={spawn_yaw:.3f}')
