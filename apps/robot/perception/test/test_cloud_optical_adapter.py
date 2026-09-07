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


import pytest
from sensor_msgs_py import point_cloud2
from std_msgs.msg import Header

FORWARD_BODY = (2.0, 0.0, 0.0)
LEFT_BODY = (2.0, 0.5, 0.0)
UP_BODY = (2.0, 0.0, 0.3)

FORWARD_OPTICAL = (0.0, 0.0, 2.0)
LEFT_OPTICAL = (-0.5, 0.0, 2.0)
UP_OPTICAL = (0.0, -0.3, 2.0)


def body_cloud(points):
    header = Header()
    header.frame_id = 'camera_0_link'
    return point_cloud2.create_cloud_xyz32(header, points)


def test_body_points_become_optical(cloud_optical_adapter_node):
    clouds = []
    cloud_optical_adapter_node.optical_cloud_publisher.publish = clouds.append
    cloud_optical_adapter_node.on_cloud(
        body_cloud([FORWARD_BODY, LEFT_BODY, UP_BODY]))
    converted = point_cloud2.read_points_numpy(
        clouds[0], field_names=('x', 'y', 'z'))
    assert converted[0] == pytest.approx(FORWARD_OPTICAL)
    assert converted[1] == pytest.approx(LEFT_OPTICAL)
    assert converted[2] == pytest.approx(UP_OPTICAL)
    assert clouds[0].header.frame_id == 'camera_0_color_optical_frame'
