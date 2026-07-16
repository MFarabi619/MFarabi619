from better_launch import BetterLaunch, launch_this


@launch_this
def control():
    bl = BetterLaunch()
    controllers = bl.find("robot_control/share", "control.yaml")
    bl.node(
        package="controller_manager",
        executable="ros2_control_node",
        name="controller_manager",
        param_files=controllers,
        remaps={"~/robot_description": "robot_description"},
    )
    bl.node(
        package="controller_manager",
        executable="spawner",
        name="joint_state_broadcaster_spawner",
        cmd_args=["joint_state_broadcaster"],
    )
    bl.node(
        package="controller_manager",
        executable="spawner",
        name="diff_drive_controller_spawner",
        cmd_args=["diff_drive_controller"],
    )
