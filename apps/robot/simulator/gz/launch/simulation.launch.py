from better_launch import BetterLaunch, launch_this


@launch_this(use_sim_time=True)
def simulation(world: str = 'maize', headless: bool = False):
    bl = BetterLaunch()
    bl.process(
        'ros2 run rmw_zenoh_cpp rmw_zenohd',
        name='zenoh_router',
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='twist_mux',
        executable='twist_mux',
        name='twist_mux',
        param_files='apps/robot/control/config/twist_mux.yaml',
        remaps={'cmd_vel_out': 'platform/cmd_vel'},
    )
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={'port': 8765},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(package='robot_perception', executable='detect_crop_row', name='crop_row_detector', max_respawns=-1, respawn_delay=2.0)
    bl.include('robot_gz', 'gz_sim.launch.py', world=world, headless=headless)
    bl.include('robot_gz', 'robot_spawn.launch.py', pass_launch_func_args=False)
