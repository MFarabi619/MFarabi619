from better_launch import BetterLaunch, convenience, launch_this

from robot.camera_stream import stream_url


@launch_this(ui=True, colormode="RAINBOW")
def robot(camera: bool = True):
    bl = BetterLaunch()

    convenience.robot_state_publisher(
        "robot", "robot.urdf", node_name="robot_state_publisher", anonymous=False
    )

    bl.node("robot", "hat_mdd10sm", "hat_mdd10sm")
    bl.node("foxglove_bridge", "foxglove_bridge", "foxglove_bridge")

    if camera:
        params = bl.load_params("robot", "camera.yaml", qualifier="camera")
        params["url"] = stream_url(params.pop("host"), params.pop("port"))
        with bl.group("camera"):
            bl.node("robot", "camera", "camera", params=params)

        # Still images via image_publisher (imread on `filename` — single files, NOT streams);
        # kept scaffolded for future static-image needs:
        # bl.node(
        #     "image_publisher",
        #     "image_publisher_node",
        #     "camera",
        #     params={"filename": params["url"], "frame_id": params["frame_id"], "publish_rate": params["publish_rate"]},
        # )
