from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='orbbec_camera',
            executable='orbbec_camera_node',
            name='camera',
            namespace='sensors/camera_0',
            parameters=[{'enable_color': True, 'color_width': 640, 'color_height': 480, 'color_fps': 30, 'color_format': 'MJPG', 'enable_depth': False, 'depth_width': 848, 'depth_height': 480, 'depth_fps': 15, 'depth_registration': False, 'align_mode': 'HW', 'enable_point_cloud': False, 'enable_noise_removal_filter': False, 'camera_name': 'camera_0'}],
        ),
    ])
