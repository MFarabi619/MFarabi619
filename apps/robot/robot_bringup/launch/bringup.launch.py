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
    bl.node(
        package="nmea_navsat_driver",
        executable="nmea_tcpclient_driver",
        name="nmea_navsat_driver",
        param_files=bl.find("robot_bringup/share", "nmea_navsat_driver.yaml"),
        remaps={"fix": "gps/fix"},
    )
    bl.include("robot_description", "description.launch.py")
    bl.include("robot_control", "control.launch.py")
