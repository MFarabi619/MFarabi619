import * as docker from "@pulumi/docker";
import * as dockerBuild from "@pulumi/docker-build";
import * as fs from "node:fs";

export function createLichtblick(network: docker.Network) {
    const image = new dockerBuild.Image("lichtblick", {
        context: { location: "../../zephyrproject/lichtblick" },
        tags: ["tandemrobotics-lichtblick:latest"],
        push: false,
        buildOnPreview: false,
        exports: [{ docker: {} }],
    });

    new docker.Container("lichtblick", {
        image: image.ref,
        name: "lichtblick",
        restart: "unless-stopped",
        uploads: [{
            file: "/lichtblick/default-layout.json",
            content: fs.readFileSync("../robot/config/lichtblick-layout.json", "utf8"),
        }],
        networksAdvanced: [{ name: network.name }],
    });
}
