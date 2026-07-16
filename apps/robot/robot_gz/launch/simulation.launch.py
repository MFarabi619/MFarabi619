from better_launch import BetterLaunch, launch_this


@launch_this
def simulation(world: str = 'maize'):
    bl = BetterLaunch()
    bl.process('ros2 run rmw_zenoh_cpp rmw_zenohd', name='zenoh_router')
    bl.node(
        package='twist_stamper',
        executable='twist_stamper',
        name='twist_stamper',
        params={'frame_id': 'base_link'},
        remaps={'cmd_vel_in': 'cmd_vel', 'cmd_vel_out': 'cmd_vel_stamped'},
    )
    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        param_files='apps/robot/robot_control/config/twist_mux.yaml',
        remaps={'cmd_vel_out': 'platform/cmd_vel'},
    )
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={'port': 8765, 'use_sim_time': True},
    )
    bl.include('robot_gz', 'gz_sim.launch.py')
    bl.include('robot_gz', 'robot_spawn.launch.py', pass_launch_func_args=False)
