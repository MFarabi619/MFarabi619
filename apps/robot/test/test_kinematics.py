import math

from robot.kinematics import (
    enu_to_geodetic,
    integrate_pose,
    normalize_angle,
    yaw_to_quaternion,
)


def test_straight_line_advances_along_heading():
    x, y, theta = integrate_pose(0.0, 0.0, 0.0, 1.0, 0.0, 1.0)
    assert math.isclose(x, 1.0, abs_tol=1e-9)
    assert math.isclose(y, 0.0, abs_tol=1e-9)
    assert math.isclose(theta, 0.0, abs_tol=1e-9)


def test_turn_in_place_changes_heading_not_position():
    x, y, theta = integrate_pose(0.0, 0.0, 0.0, 0.0, math.pi / 2.0, 1.0)
    assert math.isclose(x, 0.0, abs_tol=1e-9)
    assert math.isclose(y, 0.0, abs_tol=1e-9)
    assert math.isclose(theta, math.pi / 2.0, abs_tol=1e-9)


def test_quarter_circle_arc():
    x, y, theta = integrate_pose(0.0, 0.0, 0.0, 1.0, math.pi / 2.0, 1.0)
    assert math.isclose(x, 2.0 / math.pi, abs_tol=1e-9)
    assert math.isclose(y, 2.0 / math.pi, abs_tol=1e-9)
    assert math.isclose(theta, math.pi / 2.0, abs_tol=1e-9)


def test_normalize_angle_wraps_to_pi_interval():
    assert math.isclose(abs(normalize_angle(3.0 * math.pi)), math.pi, abs_tol=1e-9)
    assert math.isclose(normalize_angle(math.pi / 2.0 + 2.0 * math.pi), math.pi / 2.0, abs_tol=1e-9)


def test_yaw_to_quaternion_identity_and_half_turn():
    assert yaw_to_quaternion(0.0) == (0.0, 0.0, 0.0, 1.0)
    _, _, z, w = yaw_to_quaternion(math.pi)
    assert math.isclose(z, 1.0, abs_tol=1e-9)
    assert math.isclose(w, 0.0, abs_tol=1e-9)


def test_geodetic_origin_and_northward_motion():
    latitude, longitude = enu_to_geodetic(0.0, 0.0, 45.0, -75.0)
    assert math.isclose(latitude, 45.0, abs_tol=1e-12)
    assert math.isclose(longitude, -75.0, abs_tol=1e-12)

    north, _ = enu_to_geodetic(0.0, 100.0, 45.0, -75.0)
    assert north > 45.0
