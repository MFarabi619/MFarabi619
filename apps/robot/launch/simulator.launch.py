import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.substitutions import Command
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description():
    share = get_package_share_directory("robot")
    xacro_path = os.path.join(share, "urdf", "robot.urdf.xacro")
    controllers = os.path.join(share, "config", "controllers.yaml")
    twist_mux_config = os.path.join(share, "config", "twist_mux.yaml")
    robot_description = ParameterValue(Command(["xacro ", xacro_path]), value_type=str)

    return LaunchDescription(
        [
            Node(
                package="robot_state_publisher",
                executable="robot_state_publisher",
                parameters=[{"robot_description": robot_description}],
            ),
            Node(
                package="controller_manager",
                executable="ros2_control_node",
                parameters=[controllers],
                output="screen",
            ),
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["joint_state_broadcaster"],
                output="screen",
            ),
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["diff_drive_controller"],
                output="screen",
            ),
            Node(
                package="twist_mux",
                executable="twist_mux",
                parameters=[twist_mux_config],
                remappings=[("cmd_vel_out", "/diff_drive_controller/cmd_vel")],
                output="screen",
            ),
            Node(
                package="tf2_ros",
                executable="static_transform_publisher",
                arguments=["--frame-id", "map", "--child-frame-id", "odom"],
                output="screen",
            ),
            Node(package="robot", executable="simulator", name="simulator", output="screen"),
            Node(package="foxglove_bridge", executable="foxglove_bridge", output="screen"),
        ]
    )
