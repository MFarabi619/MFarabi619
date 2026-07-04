import math

from robot.kinematics import (
    enu_to_geodetic,
    wheel_angular_velocities,
    yaw_from_quaternion,
)


def test_wheel_velocities_equal_when_driving_straight():
    left, right = wheel_angular_velocities(1.0, 0.0)
    assert math.isclose(left, right)


def test_wheel_velocities_opposite_when_turning_in_place():
    left, right = wheel_angular_velocities(0.0, 1.0)
    assert math.isclose(left, -right)


def test_yaw_from_quaternion_recovers_half_pi():
    z = math.sin(math.pi / 4.0)
    w = math.cos(math.pi / 4.0)
    assert math.isclose(yaw_from_quaternion(z, w), math.pi / 2.0, abs_tol=1e-9)


def test_geodetic_origin_and_northward_motion():
    latitude, longitude = enu_to_geodetic(0.0, 0.0, 45.0, -75.0)
    assert math.isclose(latitude, 45.0, abs_tol=1e-12)
    assert math.isclose(longitude, -75.0, abs_tol=1e-12)

    north, _ = enu_to_geodetic(0.0, 100.0, 45.0, -75.0)
    assert north > 45.0
