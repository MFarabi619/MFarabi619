import os

from ament_index_python.packages import get_package_share_directory
from better_launch import BetterLaunch, launch_this


@launch_this
def robot_spawn(x: float = -9.0, y: float = -16.0, z: float = 0.5, yaw: float = -1.5708):
    bl = BetterLaunch()
    urdf = bl.find('robot_description/share', 'robot.sim.urdf')
    with open(urdf) as file:
        robot_description = file.read()
    controllers = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'control.yaml')
    robot_description = robot_description.replace(
        'package://robot_control/config/control.yaml', controllers)

    bl.node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        params={'robot_description': robot_description},
        use_sim_time=True)
    bl.node(
        package='ros_gz_sim',
        executable='create',
        name='spawn_rover',
        cmd_args=['-name', 'rover', '-topic', 'robot_description',
                  '-x', str(x), '-y', str(y), '-z', str(z), '-Y', str(yaw)])
    bl.node(
        package='controller_manager',
        executable='spawner',
        name='joint_state_broadcaster_spawner',
        cmd_args=['joint_state_broadcaster'],
        env={'ROS_SUPER_CLIENT': 'True'})
    bl.node(
        package='controller_manager',
        executable='spawner',
        name='diff_drive_controller_spawner',
        cmd_args=['diff_drive_controller', '--param-file', controllers,
                  '--controller-ros-args',
                  '-r ~/cmd_vel:=/platform/cmd_vel -r ~/reference:=/platform/cmd_vel'],
        env={'ROS_SUPER_CLIENT': 'True'})
    bl.include('robot_gz', 'robot_gz_bridges.launch.py')
