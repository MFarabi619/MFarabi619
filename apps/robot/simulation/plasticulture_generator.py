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


import os

import collada_mesh
import cv2
import numpy as np

SIMULATOR_DIR = os.path.dirname(os.path.abspath(__file__))
TARP_PHOTO_PATH = os.path.join(SIMULATOR_DIR, '..', 'assets', 'plasticulture-tarp.jpeg')

BED_LENGTH = 20.0
BED_BOTTOM_HALF_WIDTH = 0.32
BED_TOP_HALF_WIDTH = 0.18
BED_HEIGHT = 0.04
BED_COUNT = 10
BED_PITCH = 1.2
PLANT_LINE_OFFSET = 0.1
TEXTURE_METERS_PER_TILE = 1.0

CROPS = {
    'carrot': {'spacing': 0.25, 'lines': 2, 'color': (0.30, 0.60, 0.20)},
    'potato': {'spacing': 0.4, 'lines': 2, 'color': (0.22, 0.48, 0.18)},
    'onion': {'spacing': 0.25, 'lines': 2, 'color': (0.20, 0.45, 0.30)},
    'pumpkin': {'spacing': 0.9, 'lines': 1, 'color': (0.38, 0.55, 0.14)},
    'pepper': {'spacing': 0.6, 'lines': 1, 'color': (0.20, 0.42, 0.16)},
}

FLAT_TARP_LENGTH = 20.0
FLAT_TARP_WIDTH = 8.4
FLAT_TARP_CENTER_X = 0.0
FLAT_TARP_CENTER_Y = -10.2
FLAT_TARP_ROW_PITCH = 1.2
BED_CONTENTS = ['maize', 'carrot', 'potato', 'onion', 'pumpkin',
                'turtle', 'cone_red', 'cone_orange', 'cone_yellow', 'cone_blue']

CONE_PLANT_SPACING = 1.0
MAIZE_PLANT_SPACING = 0.35
TURTLE_PLANT_SPACING = 0.8
WEED_COUNT = 70
PLANT_JITTER_M = 0.04

APRILTAG_ID = 0
APRILTAG_TEXTURE_PIXELS = 400
APRILTAG_QUIET_ZONE_PIXELS = 50
APRILTAG_BLACK_EDGE_M = 0.15
APRILTAG_POST_HEIGHT_M = 0.6

FUEL_PROPS = [
    # ('House', 'hisuki/models/House', (18.5, -1.8, -0.19, 1.5708)),
    # ('walking_person', 'cyborg/models/Walking person', (11.8, -1.8, 0.0, 3.14)),
    # ('cardboard_box', 'QCforward/models/carboard box', (-13.0, -5.0, 0.0, 0.6)),
    # ('foldable_chair', 'will0993/models/foldable_chair', (-12.3, -4.0, 0.0, 1.0)),
]

mulch_texture = cv2.imread(TARP_PHOTO_PATH)[300:560, 380:620]
mulch_texture = cv2.rotate(mulch_texture, cv2.ROTATE_90_CLOCKWISE)
mulch_texture = cv2.resize(mulch_texture, (384, 384), interpolation=cv2.INTER_AREA)
mulch_texture = cv2.GaussianBlur(mulch_texture, (3, 3), 0)
cv2.imwrite(f'{SIMULATOR_DIR}/models/materials/textures/plastic_mulch.jpg', mulch_texture,
            [cv2.IMWRITE_JPEG_QUALITY, 90])




def bed_mesh(variant, texture_phase):
    half = BED_LENGTH / 2.0
    tiles = BED_LENGTH / TEXTURE_METERS_PER_TILE
    mesh = collada_mesh.TexturedMesh()
    slope = np.array([BED_BOTTOM_HALF_WIDTH - BED_TOP_HALF_WIDTH, BED_HEIGHT])
    side = slope / np.linalg.norm(slope)
    mesh.quad(
        [(-half, -BED_TOP_HALF_WIDTH, BED_HEIGHT), (half, -BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half, BED_TOP_HALF_WIDTH, BED_HEIGHT), (-half, BED_TOP_HALF_WIDTH, BED_HEIGHT)],
        (0.0, 0.0, 1.0),
        [(texture_phase, 0.3), (texture_phase + tiles, 0.3), (texture_phase + tiles, 0.7), (texture_phase, 0.7)])
    mesh.quad(
        [(-half, -BED_BOTTOM_HALF_WIDTH, 0.0), (half, -BED_BOTTOM_HALF_WIDTH, 0.0),
         (half, -BED_TOP_HALF_WIDTH, BED_HEIGHT), (-half, -BED_TOP_HALF_WIDTH, BED_HEIGHT)],
        (0.0, float(-side[1]), float(side[0])),
        [(texture_phase, 0), (texture_phase + tiles, 0), (texture_phase + tiles, 0.28), (texture_phase, 0.28)])
    mesh.quad(
        [(-half, BED_TOP_HALF_WIDTH, BED_HEIGHT), (half, BED_TOP_HALF_WIDTH, BED_HEIGHT),
         (half, BED_BOTTOM_HALF_WIDTH, 0.0), (-half, BED_BOTTOM_HALF_WIDTH, 0.0)],
        (0.0, float(side[1]), float(side[0])),
        [(texture_phase, 0.72), (texture_phase + tiles, 0.72), (texture_phase + tiles, 1.0), (texture_phase, 1.0)])
    for sign, normal in ((-1, (-1.0, 0.0, 0.0)), (1, (1.0, 0.0, 0.0))):
        x = sign * half
        corners = [(x, -BED_BOTTOM_HALF_WIDTH, 0.0), (x, -BED_TOP_HALF_WIDTH, BED_HEIGHT),
                   (x, BED_TOP_HALF_WIDTH, BED_HEIGHT), (x, BED_BOTTOM_HALF_WIDTH, 0.0)]
        if sign > 0:
            corners.reverse()
        mesh.quad(corners, normal, [(0, 0), (0.15, 0), (0.85, 0.15), (1, 0.15)])
    return collada_mesh.document(f'plasticulture_bed_{variant}', mesh.positions, mesh.normals,
                   mesh.triangles, texture='textures/plastic_mulch.jpg', uvs=mesh.uvs)


def flat_tarp_mesh():
    half_length = FLAT_TARP_LENGTH / 2.0
    half_width = FLAT_TARP_WIDTH / 2.0
    mesh = collada_mesh.TexturedMesh()
    mesh.quad(
        [(-half_length, -half_width, 0.0), (half_length, -half_width, 0.0),
         (half_length, half_width, 0.0), (-half_length, half_width, 0.0)],
        (0.0, 0.0, 1.0),
        [(0, 0), (FLAT_TARP_LENGTH, 0), (FLAT_TARP_LENGTH, FLAT_TARP_WIDTH),
         (0, FLAT_TARP_WIDTH)])
    return collada_mesh.document('flat_tarp', mesh.positions, mesh.normals, mesh.triangles,
                   texture='textures/plastic_mulch.jpg', uvs=mesh.uvs)


def dirt_mesh():
    half_length = BED_LENGTH / 2.0 + 2.0
    half_width = BED_COUNT * BED_PITCH / 2.0 + 1.0
    tiles_x = 2 * half_length / TEXTURE_METERS_PER_TILE
    tiles_y = 2 * half_width / TEXTURE_METERS_PER_TILE
    mesh = collada_mesh.TexturedMesh()
    mesh.quad(
        [(-half_length, -half_width, 0.0), (half_length, -half_width, 0.0),
         (half_length, half_width, 0.0), (-half_length, half_width, 0.0)],
        (0.0, 0.0, 1.0),
        [(0, 0), (tiles_x, 0), (tiles_x, tiles_y), (0, tiles_y)])
    return collada_mesh.document('dirt_patch', mesh.positions, mesh.normals, mesh.triangles,
                   texture='textures/dirt_diffusespecular.png', uvs=mesh.uvs)


class SolidMesh:
    def __init__(self):
        self.positions = []
        self.normals = []
        self.triangles = []

    def triangle(self, corners):
        edge_a = np.subtract(corners[1], corners[0])
        edge_b = np.subtract(corners[2], corners[0])
        normal = np.cross(edge_a, edge_b)
        length = np.linalg.norm(normal)
        normal = tuple(normal / length) if length > 0 else (0.0, 0.0, 1.0)
        for winding in (corners, corners[::-1]):
            base = len(self.positions)
            self.positions.extend(winding)
            self.normals.extend([normal if winding is corners
                                 else tuple(-value for value in normal)] * 3)
            self.triangles.append((base, base + 1, base + 2))

    def blade(self, angle, length, width, height, tilt):
        direction = np.array([np.cos(angle), np.sin(angle), 0.0])
        side = np.array([-np.sin(angle), np.cos(angle), 0.0]) * width / 2.0
        tip = direction * length * np.cos(tilt) + np.array([0, 0, height])
        self.triangle([tuple(side), tuple(-side), tuple(tip)])

    def leaf(self, angle, reach, size, height):
        direction = np.array([np.cos(angle), np.sin(angle), 0.0])
        side = np.array([-np.sin(angle), np.cos(angle), 0.0]) * size / 2.0
        stem_base = direction * reach * 0.2 + np.array([0.0, 0.0, 0.005])
        blade_base = direction * reach + np.array(
            [0.0, 0.0, max(height - size * 0.6, 0.02)])
        tip = direction * (reach + size * 0.7) + np.array(
            [0.0, 0.0, height + size * 0.6])
        self.triangle([tuple(blade_base - side), tuple(blade_base + side), tuple(tip)])
        self.triangle([tuple(blade_base - side * 0.4),
                       tuple(blade_base + side * 0.4), tuple(stem_base)])


def crop_mesh(crop):
    rng = np.random.default_rng(hash(crop) % 2 ** 31)
    mesh = SolidMesh()
    if crop == 'pepper':
        for index in range(4):
            angle = index * 2 * np.pi / 4 + rng.uniform(0, 0.6)
            mesh.blade(angle, 0.02, 0.02, 0.16 + rng.uniform(0, 0.08), 0.15)
        for index in range(16):
            angle = index * 2 * np.pi / 16 + rng.uniform(0, 0.4)
            mesh.leaf(angle, 0.02 + rng.uniform(0, 0.05), 0.07 + rng.uniform(0, 0.05),
                      0.10 + rng.uniform(0, 0.20))
    elif crop == 'onion':
        for index in range(7):
            angle = index * 2 * np.pi / 7 + rng.uniform(0, 0.4)
            mesh.blade(angle, 0.03 + rng.uniform(0, 0.02), 0.015,
                       0.18 + rng.uniform(0, 0.08), 0.1)
    elif crop == 'carrot':
        for index in range(10):
            angle = index * 2 * np.pi / 10 + rng.uniform(0, 0.3)
            mesh.blade(angle, 0.08 + rng.uniform(0, 0.04), 0.02,
                       0.10 + rng.uniform(0, 0.05), 0.5)
    elif crop == 'potato':
        for index in range(4):
            angle = index * 2 * np.pi / 4 + rng.uniform(0, 0.6)
            mesh.blade(angle, 0.02, 0.02, 0.10 + rng.uniform(0, 0.05), 0.2)
        for index in range(12):
            angle = index * 2 * np.pi / 12 + rng.uniform(0, 0.5)
            mesh.leaf(angle, 0.02 + rng.uniform(0, 0.03), 0.06 + rng.uniform(0, 0.03),
                      0.08 + rng.uniform(0, 0.10))
    else:
        for index in range(3):
            angle = index * 2 * np.pi / 3 + rng.uniform(0, 0.6)
            mesh.blade(angle, 0.03, 0.025, 0.12 + rng.uniform(0, 0.05), 0.3)
        for index in range(5):
            angle = index * 2 * np.pi / 5 + rng.uniform(0, 0.5)
            mesh.leaf(angle, 0.04 + rng.uniform(0, 0.04), 0.14 + rng.uniform(0, 0.05),
                      0.10 + rng.uniform(0, 0.08))
    return collada_mesh.document(f'{crop}_plant', mesh.positions, mesh.normals, mesh.triangles,
                   color=CROPS[crop]['color'])


MODEL_CONFIG = '''<?xml version="1.0"?>
<model>
  <name>{name}</name>
  <version>1.0</version>
  <sdf version="1.9">model.sdf</sdf>
  <author><name>Mumtahin Farabi</name><email>mfarabi619@gmail.com</email></author>
  <description>{description}</description>
</model>
'''

MODEL_SDF = '''<?xml version="1.0"?>
<sdf version="1.9">
  <model name="{name}">
    <static>true</static>
    <link name="link">
      <visual name="visual">
        <geometry><mesh><uri>model://{name}/meshes/{name}.dae</uri></mesh></geometry>
      </visual>
    </link>
  </model>
</sdf>
'''

for crop in CROPS:
    name = f'{crop}_plant'
    model_directory = f'{SIMULATOR_DIR}/models/{name}'
    os.makedirs(f'{model_directory}/meshes', exist_ok=True)
    with open(f'{model_directory}/model.config', 'w') as f:
        f.write(MODEL_CONFIG.format(name=name, description=f'Low-poly {crop} transplant'))
    with open(f'{model_directory}/model.sdf', 'w') as f:
        f.write(MODEL_SDF.format(name=name))
    with open(f'{model_directory}/meshes/{name}.dae', 'w') as f:
        f.write(crop_mesh(crop))

def apriltag_model():
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_APRILTAG_36H11)
    tag = cv2.aruco.generateImageMarker(
        dictionary, APRILTAG_ID, APRILTAG_TEXTURE_PIXELS)
    padded = cv2.copyMakeBorder(
        tag, *([APRILTAG_QUIET_ZONE_PIXELS] * 4), cv2.BORDER_CONSTANT, value=255)
    name = f'apriltag_36h11_{APRILTAG_ID}'
    model_directory = f'{SIMULATOR_DIR}/models/{name}'
    os.makedirs(f'{model_directory}/meshes', exist_ok=True)
    cv2.imwrite(f'{model_directory}/meshes/{name}.png', cv2.flip(padded, 0))
    board_edge = (APRILTAG_BLACK_EDGE_M * padded.shape[0]
                  / APRILTAG_TEXTURE_PIXELS)
    half = board_edge / 2.0
    mesh = collada_mesh.TexturedMesh()
    mesh.quad(
        [(0.0, half, -half), (0.0, -half, -half),
         (0.0, -half, half), (0.0, half, half)],
        (1.0, 0.0, 0.0),
        [(0, 0), (1, 0), (1, 1), (0, 1)])
    with open(f'{model_directory}/meshes/{name}.dae', 'w') as mesh_file:
        mesh_file.write(collada_mesh.document(name, mesh.positions, mesh.normals, mesh.triangles,
                                texture=f'{name}.png', uvs=mesh.uvs))
    with open(f'{model_directory}/model.config', 'w') as config_file:
        config_file.write(MODEL_CONFIG.format(
            name=name, description=f'AprilTag 36h11 id {APRILTAG_ID} on a post'))
    board_center = APRILTAG_POST_HEIGHT_M + half
    with open(f'{model_directory}/model.sdf', 'w') as sdf_file:
        sdf_file.write(f"""<?xml version="1.0"?>
<sdf version="1.9">
  <model name="{name}">
    <static>true</static>
    <link name="link">
      <visual name="board">
        <pose>0 0 {board_center:g} 0 0 0</pose>
        <geometry><mesh><uri>model://{name}/meshes/{name}.dae</uri></mesh></geometry>
      </visual>
      <visual name="post">
        <pose>-0.01 0 {APRILTAG_POST_HEIGHT_M / 2:g} 0 0 0</pose>
        <geometry><box><size>0.02 0.03 {APRILTAG_POST_HEIGHT_M:g}</size></box></geometry>
        <material><ambient>0.3 0.3 0.3 1</ambient><diffuse>0.5 0.5 0.5 1</diffuse></material>
      </visual>
      <collision name="collision">
        <pose>-0.01 0 {APRILTAG_POST_HEIGHT_M / 2:g} 0 0 0</pose>
        <geometry><box><size>0.02 0.03 {APRILTAG_POST_HEIGHT_M:g}</size></box></geometry>
      </collision>
    </link>
  </model>
</sdf>
""")
    return name


apriltag_name = apriltag_model()

with open(f'{SIMULATOR_DIR}/models/materials/plasticulture_bed_a.dae', 'w') as f:
    f.write(bed_mesh('a', 0.0))
with open(f'{SIMULATOR_DIR}/models/materials/plasticulture_bed_b.dae', 'w') as f:
    f.write(bed_mesh('b', 7.3))
with open(f'{SIMULATOR_DIR}/models/materials/dirt_patch.dae', 'w') as f:
    f.write(dirt_mesh())
with open(f'{SIMULATOR_DIR}/models/materials/flat_tarp.dae', 'w') as f:
    f.write(flat_tarp_mesh())

bed_centers = [(index - (BED_COUNT - 1) / 2.0) * BED_PITCH for index in range(BED_COUNT)]

beds = []
for index, center in enumerate(bed_centers):
    variant = 'ab'[index % 2]
    beds.append(f'''    <model name="bed_{index}">
      <static>true</static>
      <pose>0 {center:g} 0 0 0 0</pose>
      <link name="link">
        <visual name="visual">
          <geometry><mesh><uri>model://materials/plasticulture_bed_{variant}.dae</uri></mesh></geometry>
        </visual>
        <collision name="collision">
          <geometry><mesh><uri>model://materials/plasticulture_bed_{variant}.dae</uri></mesh></geometry>
        </collision>
      </link>
    </model>''')


jitter_rng = np.random.default_rng(20260808)


def jittered(value):
    return value + jitter_rng.uniform(-PLANT_JITTER_M, PLANT_JITTER_M)


plants = []
cones = []
for bed_index, center in enumerate(bed_centers):
    content = BED_CONTENTS[bed_index]
    if content in CROPS:
        crop_spec = CROPS[content]
        offsets = ([0.0] if crop_spec['lines'] == 1
                   else [-PLANT_LINE_OFFSET, PLANT_LINE_OFFSET])
        plant_x = np.arange(-BED_LENGTH / 2.0 + 0.4, BED_LENGTH / 2.0 - 0.3,
                            crop_spec['spacing'])
        for line_index, offset in enumerate(offsets):
            for plant_index, x in enumerate(plant_x):
                yaw = (bed_index * 131 + line_index * 37 + plant_index * 17) % 63 / 10.0
                plants.append(f'''    <include>
      <name>{content}_{bed_index}_{line_index}_{plant_index}</name>
      <uri>model://{content}_plant</uri>
      <pose>{jittered(x):.3f} {jittered(center + offset):.3f} {BED_HEIGHT:g} 0 0 {yaw:g}</pose>
    </include>''')
    elif content == 'maize':
        plant_x = np.arange(-BED_LENGTH / 2.0 + 0.4, BED_LENGTH / 2.0 - 0.3,
                            MAIZE_PLANT_SPACING)
        for plant_index, x in enumerate(plant_x):
            model = f'maize_0{plant_index % 2 + 1}'
            yaw = (bed_index * 131 + plant_index * 17) % 63 / 10.0
            plants.append(f'''    <include>
      <name>maize_{bed_index}_{plant_index}</name>
      <uri>model://{model}</uri>
      <pose>{jittered(x):.3f} {jittered(center):.3f} {BED_HEIGHT:g} 0 0 {yaw:g}</pose>
    </include>''')
    elif content == 'turtle':
        plant_x = np.arange(-BED_LENGTH / 2.0 + 0.5, BED_LENGTH / 2.0 - 0.4,
                            TURTLE_PLANT_SPACING)
        for plant_index, x in enumerate(plant_x):
            yaw = (plant_index * 29) % 63 / 10.0
            plants.append(f'''    <include>
      <name>turtle_{bed_index}_{plant_index}</name>
      <uri>https://fuel.gazebosim.org/1.0/JAMONCITO/models/turtle</uri>
      <pose>{jittered(x):.3f} {jittered(center):.3f} {BED_HEIGHT:g} 0 0 {yaw:g}</pose>
      <static>true</static>
    </include>''')
    else:
        cone_x = np.arange(-BED_LENGTH / 2.0 + 0.5, BED_LENGTH / 2.0 - 0.4,
                           CONE_PLANT_SPACING)
        for cone_index, x in enumerate(cone_x):
            cones.append(f'''    <include>
      <name>{content}_{bed_index}_{cone_index}</name>
      <uri>https://fuel.gazebosim.org/1.0/fruffers/models/{content}</uri>
      <pose>{jittered(x):.3f} {jittered(center):.3f} {BED_HEIGHT:g} 0 0 0</pose>
    </include>''')

flat_row_count = int(FLAT_TARP_WIDTH / FLAT_TARP_ROW_PITCH)
flat_row_centers = [FLAT_TARP_CENTER_Y + (index - (flat_row_count - 1) / 2.0)
                    * FLAT_TARP_ROW_PITCH for index in range(flat_row_count)]
pepper_x = np.arange(FLAT_TARP_CENTER_X - FLAT_TARP_LENGTH / 2.0 + 0.4,
                     FLAT_TARP_CENTER_X + FLAT_TARP_LENGTH / 2.0 - 0.3,
                     CROPS['pepper']['spacing'])
for row_index, row_center in enumerate(flat_row_centers):
    for plant_index, x in enumerate(pepper_x):
        yaw = (row_index * 41 + plant_index * 13) % 63 / 10.0
        plants.append(f'''    <include>
      <name>pepper_{row_index}_{plant_index}</name>
      <uri>model://pepper_plant</uri>
      <pose>{jittered(x):.3f} {jittered(row_center):.3f} 0.01 0 0 {yaw:g}</pose>
    </include>''')

weeds = []
for weed_index in range(WEED_COUNT):
    model = ('nettle', 'unknown_weed')[weed_index % 2]
    x = jitter_rng.uniform(-BED_LENGTH / 2.0 - 2.0, FLAT_TARP_CENTER_X
                           + FLAT_TARP_LENGTH / 2.0 + 1.0)
    y = jitter_rng.uniform(-BED_COUNT * BED_PITCH / 2.0 - 1.5,
                           BED_COUNT * BED_PITCH / 2.0 + 1.5)
    yaw = jitter_rng.uniform(0, 2 * np.pi)
    weeds.append(f'''    <include>
      <name>weed_{weed_index}</name>
      <uri>model://{model}</uri>
      <pose>{x:.3f} {y:.3f} 0 0 0 {yaw:.2f}</pose>
      <static>true</static>
    </include>''')
plants.extend(weeds)

plants.append(f'''    <include>
      <name>{apriltag_name}</name>
      <uri>model://{apriltag_name}</uri>
      <pose>11.5 -6.8 0 0 0 0</pose>
    </include>''')


props = []
for prop_name, fuel_path, (x, y, z, yaw) in FUEL_PROPS:
    props.append(f'''    <include>
      <name>{prop_name}</name>
      <uri>https://fuel.gazebosim.org/1.0/{fuel_path}</uri>
      <pose>{x:g} {y:g} {z:g} 0 0 {yaw:g}</pose>
      <static>true</static>
    </include>''')

beds_xml = '\n'.join(beds)
plants_xml = '\n'.join(plants)
cones_xml = '\n'.join(cones)
props_xml = '\n'.join(props)

world = f'''<?xml version="1.0"?>
<sdf version="1.9">
  <world name="plasticulture">
    <physics name="default_physics" type="ignored">
      <max_step_size>0.01</max_step_size>
      <real_time_factor>1.0</real_time_factor>
    </physics>

    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"></plugin>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"></plugin>
    <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"></plugin>
    <plugin filename="gz-sim-sensors-system" name="gz::sim::systems::Sensors">
      <render_engine>ogre2</render_engine>
    </plugin>
    <plugin filename="gz-sim-navsat-system" name="gz::sim::systems::NavSat"></plugin>
    <plugin filename="gz-sim-imu-system" name="gz::sim::systems::Imu"></plugin>

    <spherical_coordinates>
      <surface_model>EARTH_WGS84</surface_model>
      <world_frame_orientation>ENU</world_frame_orientation>
      <latitude_deg>45.395134</latitude_deg>
      <longitude_deg>-75.572868</longitude_deg>
      <elevation>70.0</elevation>
      <heading_deg>0.0</heading_deg>
    </spherical_coordinates>

    <scene>
      <ambient>0.55 0.55 0.55 1</ambient>
      <background>0.7 0.8 0.9 1</background>
      <sky><clouds><speed>2</speed></clouds></sky>
      <grid>false</grid>
    </scene>

    <light type="directional" name="sun">
      <cast_shadows>true</cast_shadows>
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

    <model name="ground_plane">
      <static>true</static>
      <link name="link">
        <collision name="collision">
          <geometry><plane><normal>0 0 1</normal><size>200 200</size></plane></geometry>
        </collision>
        <visual name="visual">
          <geometry><mesh><uri>model://materials/grass_plane.dae</uri></mesh></geometry>
        </visual>
        <visual name="dirt_visual">
          <pose>0 0 0.005 0 0 0</pose>
          <geometry><mesh><uri>model://materials/dirt_patch.dae</uri></mesh></geometry>
        </visual>
        <visual name="flat_tarp_visual">
          <pose>{FLAT_TARP_CENTER_X:g} {FLAT_TARP_CENTER_Y:g} 0.008 0 0 0</pose>
          <geometry><mesh><uri>model://materials/flat_tarp.dae</uri></mesh></geometry>
        </visual>
      </link>
    </model>

{beds_xml}

{cones_xml}

{props_xml}

{plants_xml}
  </world>
</sdf>
'''

with open(f'{SIMULATOR_DIR}/worlds/plasticulture.sdf', 'w') as f:
    f.write(world)
print(f'{BED_COUNT} beds ({", ".join(BED_CONTENTS)}), '
      f'{len(plants)} plant/weed includes, {len(cones)} cones, world written')
