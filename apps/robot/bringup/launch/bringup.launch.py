import os

from better_launch import BetterLaunch, launch_this


@launch_this
def bringup():
    os.environ["ZENOH_CONFIG_OVERRIDE"] = (
        'mode="client";connect/endpoints=["tcp/10.0.0.222:7447"]'
    )
    bl = BetterLaunch()
    bl.include("robot_bringup", "sensors.launch.py")
    bl.process("pixi run gesture", name="gesture_recognizer")
