import logging

from better_launch import BetterLaunch, launch_this


@launch_this(ui=True, colormode="RAINBOW", screen_log_level=logging.INFO)
def turtlesim():
    bl = BetterLaunch()
    bl.process("ros2 run rmw_zenoh_cpp rmw_zenohd", name="zenoh_router")
    bl.node(package="turtlesim", executable="turtlesim_node", name="turtlesim")
