import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    urdf_path = os.path.join(get_package_share_directory("robot"), "urdf", "robot.urdf")
    with open(urdf_path) as urdf_file:
        robot_description = urdf_file.read()
    return LaunchDescription(
        [
            Node(
                package="robot_state_publisher",
                executable="robot_state_publisher",
                parameters=[{"robot_description": robot_description}],
            ),
            Node(package="robot", executable="sim", name="sim", output="screen"),
            Node(package="foxglove_bridge", executable="foxglove_bridge", output="screen"),
        ]
    )
