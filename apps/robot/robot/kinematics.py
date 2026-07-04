import math

EARTH_RADIUS_METERS = 6378137.0
WHEEL_RADIUS = 0.178
WHEEL_HALF_TRACK = 0.527
WHEEL_JOINT_NAMES = ["wheel_fl_joint", "wheel_fr_joint", "wheel_rl_joint", "wheel_rr_joint"]


def wheel_angular_velocities(linear_velocity, angular_velocity):
    left = (linear_velocity - angular_velocity * WHEEL_HALF_TRACK) / WHEEL_RADIUS
    right = (linear_velocity + angular_velocity * WHEEL_HALF_TRACK) / WHEEL_RADIUS
    return left, right


def yaw_from_quaternion(qz, qw):
    return 2.0 * math.atan2(qz, qw)


def enu_to_geodetic(east_meters, north_meters, latitude_origin, longitude_origin):
    latitude = latitude_origin + math.degrees(north_meters / EARTH_RADIUS_METERS)
    longitude = longitude_origin + math.degrees(
        east_meters / (EARTH_RADIUS_METERS * math.cos(math.radians(latitude_origin)))
    )
    return latitude, longitude
