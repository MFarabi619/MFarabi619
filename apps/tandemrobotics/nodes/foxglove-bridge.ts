import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import { zenohNodeEnv } from "../robot.ts";

export function createFoxgloveBridge(network: docker.Network, robotImage: dockerBuild.Image) {
    new docker.Container("foxglove-bridge", {
        image: robotImage.ref,
        name: "foxglove-bridge",
        restart: "unless-stopped",
        envs: zenohNodeEnv,
        command: ["ros2", "run", "foxglove_bridge", "foxglove_bridge", "--ros-args",
            "-p", "send_buffer_limit:=1000000",
            "-p", "max_qos_depth:=5",
            "-p", "best_effort_qos_topic_whitelist:=['.*/sensors/camera_.*']"],
        ports: [{ internal: 8765, external: 8765 }],
        networksAdvanced: [{ name: network.name }],
    });
}
