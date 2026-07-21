from better_launch import BetterLaunch, launch_this


@launch_this
def simulation(world: str = 'maize', headless: bool = False):
    bl = BetterLaunch()
    bl.process('ros2 run rmw_zenoh_cpp rmw_zenohd', name='zenoh_router')
    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        param_files='apps/robot/robot_control/config/twist_mux.yaml',
        remaps={'cmd_vel_out': 'platform/cmd_vel'},
        use_sim_time=True,
    )
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={'port': 8765, 'use_sim_time': True},
    )
    bl.include('robot_gz', 'gz_sim.launch.py', world=world, headless=headless)
    bl.include('robot_gz', 'robot_spawn.launch.py', pass_launch_func_args=False)
