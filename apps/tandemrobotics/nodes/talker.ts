import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import { zenohNodeEnv } from "../robot.ts";

export function createTalker(network: docker.Network, robotImage: dockerBuild.Image) {
    new docker.Container("talker", {
        image: robotImage.ref,
        name: "talker",
        restart: "unless-stopped",
        envs: zenohNodeEnv,
        command: ["ros2", "topic", "pub", "-r", "1", "/chatter", "std_msgs/msg/String", "{data: 'hello from pulumi'}"],
        networksAdvanced: [{ name: network.name }],
    });
}
