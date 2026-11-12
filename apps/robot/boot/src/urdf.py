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


import xml.etree.ElementTree as ElementTree


def ground_offset_meters(urdf_path):
    robot_element = ElementTree.parse(urdf_path).getroot()
    for joint in robot_element.iter('joint'):
        child = joint.find('child')
        if child is None or child.get('link') != 'base_footprint':
            continue
        origin = joint.find('origin')
        if origin is None:
            break
        return float(origin.get('xyz', '0 0 0').split()[2])
    return 0.0


def wheel_geometry(urdf_path):
    robot_element = ElementTree.parse(urdf_path).getroot()
    joint_by_child = {}
    for joint in robot_element.iter('joint'):
        parent = joint.find('parent')
        if parent is None:
            continue
        origin = joint.find('origin')
        xyz = origin.get('xyz', '0 0 0') if origin is not None else '0 0 0'
        rpy = origin.get('rpy', '0 0 0') if origin is not None else '0 0 0'
        joint_by_child[joint.find('child').get('link')] = (
            parent.get('link'), float(xyz.split()[1]),
            any(float(angle) != 0.0 for angle in rpy.split()), joint.get('name'))

    def lateral_offset_meters(link):
        offset_meters = 0.0
        while link in joint_by_child:
            link, y, is_rotated, joint_name = joint_by_child[link]
            if is_rotated:
                raise RuntimeError(
                    f'{joint_name} has a rotated origin;'
                    ' wheel_geometry only handles pure-translation wheel chains')
            offset_meters += y
        return offset_meters

    wheel_separation = abs(
        lateral_offset_meters('rear_left_wheel_link')
        - lateral_offset_meters('rear_right_wheel_link'))

    radii_meters = {
        float(cylinder.get('radius'))
        for link in robot_element.iter('link')
        if link.get('name').endswith('_wheel_link')
        for cylinder in link.find('collision').iter('cylinder')
    }
    if len(radii_meters) != 1:
        raise RuntimeError(f'expected one wheel collision radius, found {radii_meters}')
    return wheel_separation, radii_meters.pop()
