import socket
import time

from better_launch import BetterLaunch, launch_this

ZENOH_ROUTER_PORT = 7447
ROUTER_CONFIG_OVERRIDE = (
    f'connect/endpoints=["tcp/beagleyai:{ZENOH_ROUTER_PORT}",'
    f'"tcp/pocketbeagle-2:{ZENOH_ROUTER_PORT}"]')
CLIENT_CONFIG_OVERRIDE = f'mode="client";connect/endpoints=["tcp/localhost:{ZENOH_ROUTER_PORT}"]'


def wait_for_router(attempts=50):
    for _ in range(attempts):
        try:
            socket.create_connection(
                ("127.0.0.1", ZENOH_ROUTER_PORT), timeout=0.2).close()
            return
        except OSError:
            time.sleep(0.2)


@launch_this
def bringup():
    bl = BetterLaunch()
    bl.process(
        "ros2 run rmw_zenoh_cpp rmw_zenohd",
        name="zenoh_router",
        env={"ZENOH_CONFIG_OVERRIDE": ROUTER_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    wait_for_router()
    bl.node(
        package="foxglove_bridge",
        executable="foxglove_bridge",
        name="foxglove_bridge",
        params={
            "send_buffer_limit": 1000000,
            "max_qos_depth": 5,
            "best_effort_qos_topic_whitelist": ["/sensors/camera_0/.*"],
        },
        env={"ZENOH_CONFIG_OVERRIDE": CLIENT_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package="robot_perception",
        executable="detect_hand_gestures",
        name="gesture_recognizer",
        env={"ZENOH_CONFIG_OVERRIDE": CLIENT_CONFIG_OVERRIDE},
    )
    bl.node(
        package="robot_perception",
        executable="foxglove_panels",
        name="foxglove_panels",
        env={"ZENOH_CONFIG_OVERRIDE": CLIENT_CONFIG_OVERRIDE},
    )
