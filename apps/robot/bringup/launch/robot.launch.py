import os
import socket
import time

import yaml
from better_launch import BetterLaunch, launch_this
from better_launch.convenience import robot_state_publisher

ZENOH_ROUTER_PORT = 7447
CLIENT_CONFIG_OVERRIDE = f'mode="client";connect/endpoints=["tcp/localhost:{ZENOH_ROUTER_PORT}"]'
ROUTER_CONFIG_OVERRIDE = 'mode="router"'
JAZZY_ENV = ".pixi/envs/jazzy"

GPS_TOPICS = ["fix", "vel", "time_reference", "heading"]

CONTROL_PARAM_FILES = [
    "apps/robot/control/config/control.yaml",
    "apps/robot/control/config/drivetrain.generated.yaml",
]

IMU_TOPICS = [
    "data", "mag", "linear_acceleration", "stability",
    "activity", "steps", "shake", "calibration_status",
]


def wait_for_router(attempts=120):
    for _ in range(attempts):
        try:
            socket.create_connection(
                ("127.0.0.1", ZENOH_ROUTER_PORT), timeout=0.5).close()
            return
        except OSError:
            time.sleep(1.0)


def robot_identity():
    hostname = socket.gethostname()
    robots_path = "apps/robot/config/robots"
    for robot_name in sorted(os.listdir(robots_path)):
        config_path = os.path.join(robots_path, robot_name, "robot.yaml")
        if not os.path.isfile(config_path):
            continue
        with open(config_path) as file:
            config = yaml.safe_load(file)
        for host in config["system"]["hosts"]:
            if host["hostname"] == hostname:
                return robot_name, config
    raise RuntimeError(f"no robot.yaml lists hostname {hostname}")


@launch_this
def robot():
    robot_name, robot_config = robot_identity()
    sensors = robot_config.get("sensors") or {}
    drivetrain = robot_config["platform"]["drivetrain"]
    with open("apps/robot/control/config/drivetrain.generated.yaml") as file:
        wheel_radius = yaml.safe_load(
            file)["diff_drive_controller"]["ros__parameters"]["wheel_radius"]

    bl = BetterLaunch()

    bl.process(
        "ros2 run rmw_zenoh_cpp rmw_zenohd",
        name="zenoh_router",
        env={"ZENOH_CONFIG_OVERRIDE": ROUTER_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    os.environ["ZENOH_CONFIG_OVERRIDE"] = CLIENT_CONFIG_OVERRIDE
    wait_for_router()

    with open(f"apps/robot/description/urdf/{robot_name}/robot.urdf") as file:
        robot_description = file.read()
    robot_state_publisher(
        robot_description,
        node_name="robot_state_publisher",
        anonymous=False,
    )

    bl.node(
        package="robot_drivers",
        executable="cytron_motor_driver",
        name="cytron_motor_driver",
        params={
            "gpio_chip": drivetrain["gpio_chip"],
            "pwm_frequency_hz": drivetrain["pwm_frequency_hz"],
            "max_wheel_speed": drivetrain["max_linear_velocity_mps"] / wheel_radius,
            "left_pwm_chip": drivetrain["left"]["pwm_chip"],
            "left_pwm_channel": drivetrain["left"]["pwm_channel"],
            "left_dir_pin": drivetrain["left"]["dir_pin"],
            "left_forward_level": drivetrain["left"]["forward_level"],
            "right_pwm_chip": drivetrain["right"]["pwm_chip"],
            "right_pwm_channel": drivetrain["right"]["pwm_channel"],
            "right_dir_pin": drivetrain["right"]["dir_pin"],
            "right_forward_level": drivetrain["right"]["forward_level"],
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )

    def spawn_controllers():
        if bl.is_shutdown:
            return
        bl.node(
            package="controller_manager",
            executable="spawner",
            name="controller_spawner",
            cmd_args=[
                "joint_state_broadcaster", "diff_drive_controller",
                "--param-file", "apps/robot/control/config/control.yaml",
                "--param-file", "apps/robot/control/config/drivetrain.generated.yaml",
                "--controller-manager-timeout", "60",
                "--controller-ros-args", "-r ~/cmd_vel:=/platform/cmd_vel",
            ],
        )

    bl.node(
        package="controller_manager",
        executable="ros2_control_node",
        name="controller_manager",
        remaps={"~/robot_description": "/robot_description"},
        param_files=CONTROL_PARAM_FILES,
        remap_qualifier="controller_manager",
        max_respawns=-1,
        respawn_delay=2.0,
        on_exit=spawn_controllers,
    )
    spawn_controllers()

    bl.node(
        package="twist_mux",
        executable="twist_mux",
        name="twist_mux",
        remaps={"cmd_vel_out": "/platform/cmd_vel"},
        param_files=["apps/robot/control/config/twist_mux.yaml"],
        max_respawns=-1,
        respawn_delay=2.0,
    )

    bl.node(
        package="foxglove_bridge",
        executable="foxglove_bridge",
        name="foxglove_bridge",
        params={
            "send_buffer_limit": 1000000,
            "max_qos_depth": 5,
            "best_effort_qos_topic_whitelist": ["/sensors/camera_0/.*"],
        },
        max_respawns=-1,
        respawn_delay=2.0,
    )

    bl.node(
        package="diagnostic_aggregator",
        executable="aggregator_node",
        name="diagnostic_aggregator",
        param_files=["apps/robot/diagnostics/config/diagnostic_aggregator.yaml"],
        max_respawns=-1,
        respawn_delay=2.0,
    )

    if sensors.get("gps"):
        gps_remaps = " ".join(f"-r {topic}:=sensors/gps_0/{topic}" for topic in GPS_TOPICS)
        bl.process(
            f"{JAZZY_ENV}/lib/nmea_navsat_driver/nmea_serial_driver"
            f" --ros-args -r __node:=nmea_navsat_driver {gps_remaps}"
            " --params-file apps/robot/bringup/config/generated/"
            f"{robot_name}/nmea_navsat_driver.yaml",
            name="nmea_navsat_driver",
            max_respawns=-1,
            respawn_delay=2.0,
        )

    if sensors.get("imu"):
        bl.node(
            package="robot_sensors",
            executable="imu",
            name="imu_0",
            remaps={topic: f"/sensors/imu_0/{topic}" for topic in IMU_TOPICS},
            param_files=[f"apps/robot/bringup/config/generated/{robot_name}/imu_0.yaml"],
            max_respawns=-1,
            respawn_delay=2.0,
        )

    orbbec_camera = next(
        (camera for camera in sensors.get("camera", [])
         if camera["model"] == "orbbec_gemini_335l"
         and camera.get("launch_enabled", True)),
        None)
    if orbbec_camera:
        camera_parameters = next(iter(orbbec_camera["ros_parameters"].values()))
        bl.process(
            f"{JAZZY_ENV}/bin/python"
            " apps/robot/sensors/orbbec_camera.py"
            " --ros-args -r __ns:=/sensors/camera_0"
            f" -p width:={camera_parameters['color_width']}"
            f" -p height:={camera_parameters['color_height']}"
            f" -p fps:={camera_parameters['color_fps']}",
            name="orbbec_gemini_335l",
            max_respawns=-1,
            respawn_delay=2.0,
        )
