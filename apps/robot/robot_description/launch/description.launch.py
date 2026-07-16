from better_launch import BetterLaunch, launch_this


@launch_this
def description():
    bl = BetterLaunch()
    urdf = bl.find("robot_description/share", "robot.urdf")
    with open(urdf) as file:
        robot_description = file.read()
    bl.node(
        package="robot_state_publisher",
        executable="robot_state_publisher",
        name="robot_state_publisher",
        params={"robot_description": robot_description},
    )
