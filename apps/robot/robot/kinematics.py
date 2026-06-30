import math

EARTH_RADIUS_METERS = 6378137.0


def normalize_angle(angle):
    return math.atan2(math.sin(angle), math.cos(angle))


def integrate_pose(x, y, theta, linear_velocity, angular_velocity, dt):
    if abs(angular_velocity) < 1e-6:
        x += linear_velocity * math.cos(theta) * dt
        y += linear_velocity * math.sin(theta) * dt
        return x, y, normalize_angle(theta)
    theta_next = theta + angular_velocity * dt
    turn_radius = linear_velocity / angular_velocity
    x += turn_radius * (math.sin(theta_next) - math.sin(theta))
    y -= turn_radius * (math.cos(theta_next) - math.cos(theta))
    return x, y, normalize_angle(theta_next)


def yaw_to_quaternion(theta):
    return 0.0, 0.0, math.sin(theta / 2.0), math.cos(theta / 2.0)


def enu_to_geodetic(east_meters, north_meters, latitude_origin, longitude_origin):
    latitude = latitude_origin + math.degrees(north_meters / EARTH_RADIUS_METERS)
    longitude = longitude_origin + math.degrees(
        east_meters / (EARTH_RADIUS_METERS * math.cos(math.radians(latitude_origin)))
    )
    return latitude, longitude
