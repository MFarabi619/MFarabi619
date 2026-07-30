import os
import subprocess
import threading
import time

from better_launch import BetterLaunch, launch_this

PIXI = os.path.expanduser("~/.pixi/bin/pixi")
ACTIVATION_RETRY_SECONDS = 3.0
LIFECYCLE_CLI_TIMEOUT_SECONDS = 15


def ros2_lifecycle(*arguments):
    return subprocess.run(
        ["timeout", str(LIFECYCLE_CLI_TIMEOUT_SECONDS), "ros2", "lifecycle", *arguments],
        capture_output=True,
        text=True,
    )


def activate_slam_toolbox(bl):
    transitions = {"unconfigured": "configure", "inactive": "activate"}
    while True:
        time.sleep(ACTIVATION_RETRY_SECONDS)
        try:
            lines = ros2_lifecycle("get", "/slam_toolbox").stdout.strip().splitlines()
            state = lines[-1].split(" ")[0] if lines else ""
            if state == "active":
                bl.logger.info("slam_toolbox active")
                return
            if state in transitions:
                ros2_lifecycle("set", "/slam_toolbox", transitions[state])
        except Exception as error:
            bl.logger.warning(f"slam_toolbox activation attempt failed: {error}")


@launch_this
def slam(env: str = 'jazzy', use_sim_time: bool = False,
         scan_topic: str = '/sensors/camera_0/scan'):
    bl = BetterLaunch()
    env_path = os.path.abspath(f".pixi/envs/{env}")
    bl.process(
        f"{PIXI} run --clean-env -e {env}"
        f" {env_path}/lib/slam_toolbox/sync_slam_toolbox_node"
        " --ros-args -r __node:=slam_toolbox"
        " --params-file apps/robot/navigation/config/slam.yaml"
        f" -p scan_topic:={scan_topic}"
        f" -p use_sim_time:={'true' if use_sim_time else 'false'}",
        name="slam_toolbox",
        env={"HOME": os.environ["HOME"]},
        isolate_env=True,
    )
    threading.Thread(target=activate_slam_toolbox, args=(bl,), daemon=True).start()
