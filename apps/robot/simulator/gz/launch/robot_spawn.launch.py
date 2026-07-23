import os

from ament_index_python.packages import get_package_share_directory
from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher


@launch_this(use_sim_time=True)
def robot_spawn(robot: str = 'robot0', x: float = 0.316, y: float = 14.241,
                z: float = 0.67, yaw: float = -1.5708):
    bl = BetterLaunch()
    urdf_path = bl.find('robot_description/share', 'robot.sim.urdf', subdir=f'urdf/{robot}')
    with open(urdf_path) as file:
        robot_description = file.read()
    control_config_path = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'control.yaml')
    drivetrain_config_path = os.path.join(
        get_package_share_directory('robot_control'), 'config', 'drivetrain.generated.yaml')
    robot_description = robot_description.replace(
        'package://robot_control/config/control.yaml', control_config_path)

    robot_state_publisher(
        robot_description,
        node_name='robot_state_publisher',
        anonymous=False,
    )
    bl.node(
        package='ros_gz_sim',
        executable='create',
        name='robot_spawn',
        cmd_args=['-name', 'robot', '-topic', 'robot_description',
                  '-x', str(x), '-y', str(y), '-z', str(z), '-Y', str(yaw)])
    def shutdown_if_spawner_failed():
        if spawner._process.returncode != 0 and not bl.is_shutdown:
            bl._shutdown_future.set_result(None)
            bl.shutdown('controller spawn failed, refusing to run an undrivable sim')

    spawner = bl.node(
        package='controller_manager',
        executable='spawner',
        name='controller_spawner',
        cmd_args=['joint_state_broadcaster', 'diff_drive_controller',
                  '--param-file', control_config_path,
                  '--param-file', drivetrain_config_path,
                  '--controller-manager-timeout', '60',
                  '--controller-ros-args',
                  '-r ~/cmd_vel:=/platform/cmd_vel -r ~/reference:=/platform/cmd_vel'],
        env={'ROS_SUPER_CLIENT': 'True'},
        on_exit=shutdown_if_spawner_failed)
    bl.include('robot_gz', 'robot_gz_bridges.launch.py', subdir=f'launch/generated/{robot}')
