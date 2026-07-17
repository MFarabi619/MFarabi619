from better_launch import BetterLaunch, launch_this


@launch_this
def control():
    bl = BetterLaunch()
    controllers = bl.find("robot_control/share", "control.yaml")
    drivetrain = bl.find("robot_control/share", "drivetrain.generated.yaml")
    twist_mux_config = bl.find("robot_control/share", "twist_mux.yaml")
    bl.node(
        package="controller_manager",
        executable="ros2_control_node",
        name="controller_manager",
        param_files=controllers,
        remaps={"~/robot_description": "robot_description"},
    )
    bl.node(
        package="twist_stamper",
        executable="twist_stamper",
        name="twist_stamper",
        params={"frame_id": "base_link"},
        remaps={"cmd_vel_in": "cmd_vel", "cmd_vel_out": "cmd_vel_stamped"},
    )
    bl.node(
        package="twist_mux",
        executable="twist_mux",
        name="twist_mux",
        param_files=twist_mux_config,
        remaps={"cmd_vel_out": "platform/cmd_vel"},
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
        cmd_args=[
            "diff_drive_controller", "--param-file", controllers, "--param-file", drivetrain,
            "--controller-ros-args", "-r ~/cmd_vel:=/platform/cmd_vel",
        ],
    )
