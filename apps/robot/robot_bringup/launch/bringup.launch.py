from better_launch import BetterLaunch, launch_this


@launch_this
def bringup():
    bl = BetterLaunch()
    bl.process("ros2 run rmw_zenoh_cpp rmw_zenohd", name="zenoh_router")
    bl.node(
        package="foxglove_bridge",
        executable="foxglove_bridge",
        name="foxglove_bridge",
        params={"port": 8765},
    )
    bl.include("robot_bringup", "sensors.launch.py")
    bl.include("robot_description", "description.launch.py")
    bl.include("robot_control", "control.launch.py")
    bl.process("pixi run gesture", name="gesture_recognizer")
