import * as docker from "@pulumi/docker";

const caddyfile = `:80 {
	reverse_proxy homepage:3000
}

lichtblick.localhost:80 {
	reverse_proxy lichtblick:8080
}
`;

export function createCaddy(network: docker.Network) {
    const image = new docker.RemoteImage("caddy", {
        name: "caddy:2.11.4",
        keepLocally: true,
    });

    new docker.Container("caddy", {
        image: image.imageId,
        name: "caddy",
        restart: "unless-stopped",
        uploads: [{ file: "/etc/caddy/Caddyfile", content: caddyfile }],
        ports: [{ internal: 80, external: 80 }],
        networksAdvanced: [{ name: network.name }],
    });
}
