import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import { zenohNodeEnv } from "../robot.ts";

export function createTwistMux(network: docker.Network, robotImage: dockerBuild.Image, robot: string) {
    new docker.Container(`${robot}-twist-mux`, {
        image: robotImage.ref,
        name: `${robot}-twist-mux`,
        restart: "unless-stopped",
        envs: zenohNodeEnv,
        command: ["ros2", "run", "twist_mux", "twist_mux", "--ros-args",
            "-r", `__ns:=/${robot}`,
            "--params-file", "/src/apps/robot/control/config/twist_mux.yaml",
            "-r", "cmd_vel_out:=platform/cmd_vel",
            "-p", "use_sim_time:=true"],
        networksAdvanced: [{ name: network.name }],
    });
}
