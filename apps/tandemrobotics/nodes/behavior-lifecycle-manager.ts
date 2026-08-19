import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import { zenohNodeEnv } from "../robot.ts";

const jazzyEnvironment = "/src/apps/robot/.pixi/envs/jazzy";

export function createBehaviorLifecycleManager(network: docker.Network, robotImage: dockerBuild.Image, robot: string) {
    new docker.Container(`${robot}-behavior-lifecycle-manager`, {
        image: robotImage.ref,
        name: `${robot}-behavior-lifecycle-manager`,
        restart: "unless-stopped",
        envs: zenohNodeEnv,
        entrypoints: ["/bin/bash", "/entrypoint-jazzy.sh"],
        command: [`${jazzyEnvironment}/lib/nav2_lifecycle_manager/lifecycle_manager`, "--ros-args",
            "-r", "__node:=behavior_lifecycle_manager",
            "-r", `__ns:=/${robot}`,
            "-p", "autostart:=true",
            "-p", "node_names:=[behavior_server]",
            "-p", "bond_timeout:=0.0",
            "-p", "use_sim_time:=true"],
        networksAdvanced: [{ name: network.name }],
    });
}
