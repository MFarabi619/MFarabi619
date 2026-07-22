import glob
import os

from ament_index_python.packages import get_package_share_directory
from better_launch import BetterLaunch, launch_this


def generated(prefix):
    config_dir = os.path.join(
        get_package_share_directory("robot_bringup"), "config", "generated"
    )
    for config in sorted(glob.glob(os.path.join(config_dir, f"{prefix}_*.yaml"))):
        yield os.path.splitext(os.path.basename(config))[0]


@launch_this
def sensors():
    bl = BetterLaunch()
    for camera in generated("camera"):
        with bl.group(f"sensors/{camera}"):
            bl.node(
                package="robot_camera",
                executable="mjpeg_camera",
                name="camera",
                params=bl.load_params(
                    "robot_bringup/share",
                    f"{camera}.yaml",
                    qualifier=camera,
                ),
                max_respawns=-1,
                respawn_delay=2.0,
            )
    for ptu in generated("ptu"):
        with bl.group(f"sensors/{ptu}"):
            bl.node(
                package="robot_ptu",
                executable="ptu_driver",
                name="ptu_driver",
                params=bl.load_params(
                    "robot_bringup/share",
                    f"{ptu}.yaml",
                    qualifier=ptu,
                ),
                remaps={"state": "/joint_states"},
            )
            bl.node(
                package="robot_ptu",
                executable="ptu_aim",
                name="ptu_aim",
            )
    with bl.group("sensors/camera_0"):
        bl.node(
            package="depth_image_proc",
            executable="point_cloud_xyzrgb_node",
            name="point_cloud_xyzrgb",
            params={
                "image_transport": "compressed",
                "depth_image_transport": "compressedDepth",
            },
            remaps={
                "rgb/image_rect_color": "/sensors/camera_0/color/image_raw",
                "rgb/camera_info": "/sensors/camera_0/color/camera_info",
                "depth_registered/image_rect": "/sensors/camera_0/depth/image_raw",
            },
        )
