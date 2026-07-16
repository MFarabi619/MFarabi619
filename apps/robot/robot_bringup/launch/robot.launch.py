from better_launch import BetterLaunch, launch_this


@launch_this
def robot(platform: str = "rover"):
    bl = BetterLaunch()
    control = f"apps/robot/robot_config/{platform}/control.yaml"
    generated = "apps/robot/robot_bringup/config/generated"
    bl.process("ros2 run rmw_zenoh_cpp rmw_zenohd", name="zenoh_router")
    bl.include("robot_description", "description.launch.py")
    bl.node(
        package="twist_mux",
        executable="twist_mux",
        name="twist_mux",
        param_files="apps/robot/robot_control/config/twist_mux.yaml",
        remaps={"cmd_vel_out": "platform/cmd_vel"},
    )
    bl.process(
        f"target/release/base_controller --ros-args"
        f" --params-file {control}"
        f" --params-file {generated}/camera.yaml"
        f" --params-file {generated}/gps.yaml",
        name="base_controller",
    )
