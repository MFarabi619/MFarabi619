import * as dockerBuild from "@pulumi/docker-build";

export const zenohNodeEnv = [
    "RMW_IMPLEMENTATION=rmw_zenoh_cpp",
    `ZENOH_CONFIG_OVERRIDE=mode="client";connect/endpoints=["tcp/zenoh-router:7447"]`,
];

export function buildRobotImage(): dockerBuild.Image {
    return new dockerBuild.Image("robot", {
        dockerfile: {
            inline: `
FROM ghcr.io/prefix-dev/pixi:0.76.1 AS build
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
WORKDIR /src/apps/robot
COPY . .
COPY --from=better_launch . /src/zephyrproject/modules/lib/better_launch
RUN pixi install --locked
RUN pixi install --locked -e jazzy
RUN pixi run build
RUN pixi shell-hook -s bash > /entrypoint.sh && echo 'exec "$@"' >> /entrypoint.sh
RUN echo 'exec "$@"' > /entrypoint-jazzy.sh

FROM ubuntu:24.04
WORKDIR /src/apps/robot
COPY --from=build /src/apps/robot/.pixi/envs/default /src/apps/robot/.pixi/envs/default
COPY --from=build /src/apps/robot/.pixi/envs/jazzy /src/apps/robot/.pixi/envs/jazzy
COPY --from=build /src/apps/robot/install /src/apps/robot/install
COPY --from=build --chmod=0755 /entrypoint.sh /entrypoint.sh
COPY --from=build --chmod=0755 /entrypoint-jazzy.sh /entrypoint-jazzy.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
`,
        },
        context: {
            location: "../robot",
            named: {
                better_launch: { location: "../../zephyrproject/modules/lib/better_launch" },
            },
        },
        tags: ["tandemrobotics-robot:latest"],
        push: false,
        buildOnPreview: false,
        exports: [{ docker: {} }],
    });
}
