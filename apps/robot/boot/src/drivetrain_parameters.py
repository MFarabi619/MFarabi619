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

import yaml

CONTROLLER_PARAMETERS_BY_LIMIT = {
    'max_linear_velocity_meters_per_second': 'linear.x.max_velocity',
    'max_linear_acceleration_meters_per_second_squared': 'linear.x.max_acceleration',
    'max_linear_jerk_meters_per_second_cubed': 'linear.x.max_jerk',
    'max_angular_velocity_radians_per_second': 'angular.z.max_velocity',
    'max_angular_acceleration_radians_per_second_squared': 'angular.z.max_acceleration',
    'max_angular_jerk_radians_per_second_cubed': 'angular.z.max_jerk',
}
CONTROLLER_MANAGER_TIMEOUT_SECONDS = '60'


def write_drivetrain_parameters_file(wheel_separation, wheel_radius, motion_limits):
    ros_parameters = {
        'wheel_separation': wheel_separation,
        'wheel_radius': wheel_radius,
    }
    for limit, controller_parameter in CONTROLLER_PARAMETERS_BY_LIMIT.items():
        if motion_limits.get(limit):
            ros_parameters[controller_parameter] = motion_limits[limit]
    parameters = {
        '/**/diff_drive_controller': {'ros__parameters': ros_parameters},
    }
    parameters_tempfile = tempfile.NamedTemporaryFile(
        mode='w', prefix='drivetrain_', suffix='.yaml', delete=False)
    yaml.safe_dump(parameters, parameters_tempfile)
    parameters_tempfile.close()
    return parameters_tempfile.name
