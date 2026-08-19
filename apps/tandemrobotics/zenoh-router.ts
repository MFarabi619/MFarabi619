import * as docker from "@pulumi/docker";

export function createZenohRouter(network: docker.Network) {
    const image = new docker.RemoteImage("zenoh-router", {
        name: "eclipse/zenoh:1.9.0",
        keepLocally: true,
    });

    new docker.Container("zenoh-router", {
        image: image.imageId,
        name: "zenoh-router",
        restart: "unless-stopped",
        envs: ["RUST_LOG=zenoh=info"],
        ports: [{ internal: 7447, external: 7447 }],
        networksAdvanced: [{ name: network.name }],
    });
}
