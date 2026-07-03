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
            Node(package="robot", executable="hat_mdd10sm", name="hat_mdd10sm", output="screen"),
            Node(
                package="usb_cam",
                executable="usb_cam_node_exe",
                namespace="camera",
                name="camera",
                parameters=[
                    {
                        "video_device": "/dev/video0",
                        "pixel_format": "mjpeg2rgb",
                        "image_width": 1920,
                        "image_height": 1200,
                        "framerate": 90.0,
                    }
                ],
                output="screen",
            ),
            Node(
                package="apriltag_ros",
                executable="apriltag_node",
                name="apriltag",
                remappings=[
                    ("image_rect", "/camera/image_raw"),
                    ("camera_info", "/camera/camera_info"),
                ],
                parameters=[{"family": "36h11", "size": 0.1}],
                output="screen",
            ),
            Node(package="foxglove_bridge", executable="foxglove_bridge", output="screen"),
        ]
    )
