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

"""COLLADA meshes shared by the world generators."""

import math
import re
from typing import NamedTuple
import xml.etree.ElementTree as ElementTree


class SourceMesh(NamedTuple):
    positions: list
    normals: list
    uvs: list
    triangles: list
    texture: str
    color: str


def read_mesh(path):
    root = ElementTree.parse(path).getroot()
    namespace = re.match(r'\{(.*)\}', root.tag).group(1)

    def tag(name):
        return f'{{{namespace}}}{name}'

    mesh = next(root.iter(tag('mesh')))
    arrays = {}
    for source in mesh.iter(tag('source')):
        accessor = source.find(f'{tag("technique_common")}/{tag("accessor")}')
        stride = int(accessor.get('stride'))
        values = [float(value)
                  for value in source.find(tag('float_array')).text.split()]
        arrays[source.get('id')] = [
            values[start:start + stride] for start in range(0, len(values), stride)]

    position_source = {
        vertices.get('id'): vertices.find(tag('input')).get('source').lstrip('#')
        for vertices in mesh.iter(tag('vertices'))}

    faces = next(mesh.iter(tag('triangles')))
    inputs = {}
    for element in faces.findall(tag('input')):
        source = element.get('source').lstrip('#')
        inputs[element.get('semantic')] = (
            int(element.get('offset')), position_source.get(source, source))
    stride = max(offset for offset, _ in inputs.values()) + 1
    indices = [int(value) for value in faces.find(tag('p')).text.split()]

    positions, normals, uvs = [], [], []
    for start in range(0, len(indices), stride):
        corner = indices[start:start + stride]
        for semantic, target in (('VERTEX', positions), ('NORMAL', normals),
                                 ('TEXCOORD', uvs)):
            if semantic not in inputs:
                continue
            offset, source = inputs[semantic]
            target.append(arrays[source][corner[offset]][:3 if target is not uvs else 2])

    image = next(root.iter(tag('image')), None)
    color = next(root.iter(tag('color')), None)
    return SourceMesh(
        positions, normals, uvs,
        [(index, index + 1, index + 2) for index in range(0, len(positions), 3)],
        image.find(tag('init_from')).text if image is not None else None,
        tuple(float(value) for value in color.text.split()[:3])
        if color is not None else None)


def replicated(source, placements, scale=1.0):
    positions, normals, uvs = [], [], []
    scaled = [(px * scale, py * scale, pz * scale) for px, py, pz in source.positions]
    axes = list(zip(*scaled))
    anchor = ((min(axes[0]) + max(axes[0])) / 2.0,
              (min(axes[1]) + max(axes[1])) / 2.0,
              min(axes[2]))
    scaled = [(px - anchor[0], py - anchor[1], pz - anchor[2]) for px, py, pz in scaled]
    for x, y, z, yaw in placements:
        cosine, sine = math.cos(yaw), math.sin(yaw)
        positions.extend(
            (px * cosine - py * sine + x, px * sine + py * cosine + y, pz + z)
            for px, py, pz in scaled)
        normals.extend(
            (nx * cosine - ny * sine, nx * sine + ny * cosine, nz)
            for nx, ny, nz in source.normals)
        uvs.extend(source.uvs)
    return SourceMesh(
        positions, normals, uvs,
        [(index, index + 1, index + 2) for index in range(0, len(positions), 3)],
        source.texture, source.color)


def floats(values):
    return ' '.join(f'{value:g}' for row in values for value in row)


def faces_away(corners, normal):
    first = [corners[1][axis] - corners[0][axis] for axis in range(3)]
    second = [corners[2][axis] - corners[0][axis] for axis in range(3)]
    winding = (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )
    return sum(winding[axis] * normal[axis] for axis in range(3)) < 0.0


class TexturedMesh:
    def __init__(self):
        self.positions = []
        self.normals = []
        self.uvs = []
        self.triangles = []

    def quad(self, corners, normal, uv_corners):
        base = len(self.positions)
        self.positions.extend(corners)
        self.normals.extend([normal] * 4)
        self.uvs.extend(uv_corners)
        # A quad wound against its own normal renders as a hole once the engine
        # culls back faces, so the winding follows the normal rather than the
        # order the corners happened to be written in.
        if faces_away(corners, normal):
            self.triangles.append((base, base + 2, base + 1))
            self.triangles.append((base, base + 3, base + 2))
        else:
            self.triangles.append((base, base + 1, base + 2))
            self.triangles.append((base, base + 2, base + 3))


def document(geometry_id, positions, normals, triangles, texture=None, uvs=None,
             color=None):
    position_count = len(positions)
    if texture:
        image_library = (
            f'<library_images><image id="{geometry_id}_image">'
            f'<init_from>{texture}</init_from></image></library_images>')
        surface = (
            f'<newparam sid="{geometry_id}_surface"><surface type="2D">'
            f'<init_from>{geometry_id}_image</init_from></surface></newparam>'
            f'<newparam sid="{geometry_id}_sampler"><sampler2D>'
            f'<source>{geometry_id}_surface</source>'
            f'<wrap_s>WRAP</wrap_s><wrap_t>WRAP</wrap_t></sampler2D></newparam>')
        diffuse = f'<texture texture="{geometry_id}_sampler" texcoord="UVSET0"/>'
        uv_source = f'''
        <source id="{geometry_id}_uv">
          <float_array id="{geometry_id}_uv_array" count="{position_count * 2}">{floats(uvs)}</float_array>
          <technique_common><accessor source="#{geometry_id}_uv_array" count="{position_count}" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common>
        </source>'''
        uv_input = f'<input semantic="TEXCOORD" source="#{geometry_id}_uv" offset="2" set="0"/>'
        bind_uv = '<bind_vertex_input semantic="UVSET0" input_semantic="TEXCOORD" input_set="0"/>'
        normal_offset = 1
        triangle_entries = ' '.join(
            f'{index} {index} {index}' for triangle in triangles for index in triangle)
    else:
        image_library = ''
        surface = ''
        red, green, blue = color
        diffuse = f'<color>{red} {green} {blue} 1</color>'
        uv_source = ''
        uv_input = ''
        bind_uv = ''
        normal_offset = 0
        triangle_entries = ' '.join(
            str(index) for triangle in triangles for index in triangle)
    return f'''<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>
  {image_library}
  <library_effects>
    <effect id="{geometry_id}_effect">
      <profile_COMMON>
        {surface}
        <technique sid="common"><lambert><diffuse>{diffuse}</diffuse></lambert></technique>
      </profile_COMMON>
    </effect>
  </library_effects>
  <library_materials>
    <material id="{geometry_id}_material"><instance_effect url="#{geometry_id}_effect"/></material>
  </library_materials>
  <library_geometries>
    <geometry id="{geometry_id}_geometry">
      <mesh>
        <source id="{geometry_id}_positions">
          <float_array id="{geometry_id}_positions_array" count="{position_count * 3}">{floats(positions)}</float_array>
          <technique_common><accessor source="#{geometry_id}_positions_array" count="{position_count}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common>
        </source>
        <source id="{geometry_id}_normals">
          <float_array id="{geometry_id}_normals_array" count="{position_count * 3}">{floats(normals)}</float_array>
          <technique_common><accessor source="#{geometry_id}_normals_array" count="{position_count}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common>
        </source>{uv_source}
        <vertices id="{geometry_id}_vertices"><input semantic="POSITION" source="#{geometry_id}_positions"/></vertices>
        <triangles material="{geometry_id}_material" count="{len(triangles)}">
          <input semantic="VERTEX" source="#{geometry_id}_vertices" offset="0"/>
          <input semantic="NORMAL" source="#{geometry_id}_normals" offset="{normal_offset}"/>
          {uv_input}
          <p>{triangle_entries}</p>
        </triangles>
      </mesh>
    </geometry>
  </library_geometries>
  <library_visual_scenes>
    <visual_scene id="{geometry_id}_scene">
      <node id="{geometry_id}_node">
        <instance_geometry url="#{geometry_id}_geometry">
          <bind_material><technique_common>
            <instance_material symbol="{geometry_id}_material" target="#{geometry_id}_material">{bind_uv}</instance_material>
          </technique_common></bind_material>
        </instance_geometry>
      </node>
    </visual_scene>
  </library_visual_scenes>
  <scene><instance_visual_scene url="#{geometry_id}_scene"/></scene>
</COLLADA>
'''
