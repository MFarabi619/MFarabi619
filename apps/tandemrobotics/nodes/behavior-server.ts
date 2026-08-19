import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import { zenohNodeEnv } from "../robot.ts";

const jazzyEnvironment = "/src/apps/robot/.pixi/envs/jazzy";

export function createBehaviorServer(network: docker.Network, robotImage: dockerBuild.Image, robot: string) {
    new docker.Container(`${robot}-behavior-server`, {
        image: robotImage.ref,
        name: `${robot}-behavior-server`,
        restart: "unless-stopped",
        envs: zenohNodeEnv,
        entrypoints: ["/bin/bash", "/entrypoint-jazzy.sh"],
        command: [`${jazzyEnvironment}/lib/nav2_behaviors/behavior_server`, "--ros-args",
            "-r", "__node:=behavior_server",
            "-r", `__ns:=/${robot}`,
            "--params-file", "/src/apps/robot/navigation/config/behaviors.yaml",
            "-p", "use_sim_time:=true"],
        networksAdvanced: [{ name: network.name }],
    });
}
