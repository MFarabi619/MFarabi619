from better_launch import BetterLaunch, launch_this


@launch_this
def slam(robot: str = '', use_sim_time: bool = False, scan_topic: str = ''):
    bl = BetterLaunch()
    if not scan_topic:
        scan_topic = (f'/{robot}/sensors/camera_0/scan' if robot
                      else '/sensors/camera_0/scan')
    tf_remaps = ({'/tf': f'/{robot}/tf', '/tf_static': f'/{robot}/tf_static'}
                 if robot else {})
    bl.node(
        package='slam_toolbox',
        executable='sync_slam_toolbox_node',
        name='slam_toolbox',
        params={'scan_topic': scan_topic, 'use_sim_time': use_sim_time},
        param_files=['navigation/config/slam.yaml'],
        remaps=tf_remaps,
    )
