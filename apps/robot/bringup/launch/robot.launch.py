import os

from better_launch import BetterLaunch, launch_this


@launch_this
def robot(platform: str = "rover"):
    os.environ["ZENOH_CONFIG_OVERRIDE"] = (
        'mode="client";connect/endpoints=["tcp/10.0.0.222:7447"]'
    )
    bl = BetterLaunch()
    control = f"apps/robot/config/{platform}/control.yaml"
    generated = "apps/robot/bringup/config/generated"
    bl.node(
        package="twist_mux",
        executable="twist_mux",
        name="twist_mux",
        param_files="apps/robot/control/config/twist_mux.yaml",
        remaps={"cmd_vel_out": "platform/cmd_vel"},
    )
    bl.process(
        f"target/release/base_controller --ros-args"
        f" --params-file {control}"
        f" --params-file {generated}/gps.yaml",
        name="base_controller",
    )
