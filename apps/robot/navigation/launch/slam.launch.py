import os
import shlex
import threading
import time

from better_launch import BetterLaunch, launch_this

ACTIVATION_RETRY_S = 3.0
ROS_CONNECT_TIMEOUT_S = 5.0
LIFECYCLE_PROBE_TIMEOUT_S = 0.5


def activate_slam_toolbox(bl, node):
    while True:
        try:
            if (node.is_ros2_connected(timeout=ROS_CONNECT_TIMEOUT_S)
                    and node.is_lifecycle_node(timeout=LIFECYCLE_PROBE_TIMEOUT_S)
                    and node.lifecycle.transition("active")):
                bl.logger.info("slam_toolbox active")
                return
        except Exception as error:
            bl.logger.warning(f"slam_toolbox activation attempt failed: {error}")
        time.sleep(ACTIVATION_RETRY_S)


@launch_this
def slam(robot: str = '', environment: str = 'jazzy', use_sim_time: bool = False,
         scan_topic: str = ''):
    bl = BetterLaunch()
    if not scan_topic:
        scan_topic = (f'/{robot}/sensors/camera_0/scan' if robot
                      else '/sensors/camera_0/scan')
    environment_path = os.path.abspath(f".pixi/envs/{environment}")
    zenoh_override = os.environ.get('ZENOH_CONFIG_OVERRIDE')
    environment_overrides = (
        f" /usr/bin/env ZENOH_CONFIG_OVERRIDE={shlex.quote(zenoh_override)}"
        if zenoh_override else '')
    tf_remaps = (f" -r /tf:=/{robot}/tf -r /tf_static:=/{robot}/tf_static"
                 if robot else '')
    node = bl.process(
        f"pixi run --clean-env -e {environment}"
        f"{environment_overrides}"
        f" {environment_path}/lib/slam_toolbox/sync_slam_toolbox_node"
        " --ros-args -r __node:=slam_toolbox"
        f"{tf_remaps}"
        " --params-file navigation/config/slam.yaml"
        f" -p scan_topic:={scan_topic}"
        f" -p use_sim_time:={'true' if use_sim_time else 'false'}",
        name="slam_toolbox",
        env={"HOME": os.environ["HOME"], "PATH": os.environ["PATH"]},
        isolate_env=True,
    )
    threading.Thread(
        target=activate_slam_toolbox, args=(bl, node), daemon=True).start()
