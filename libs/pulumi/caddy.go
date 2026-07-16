package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createCaddy(ctx *pulumi.Context, network *docker.Network) error {
	image, err := pullImage(ctx, "caddy", "caddy:latest")
	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "caddy", &docker.ContainerArgs{
		Image:   image.ImageId,
		Name:    pulumi.String("caddy"),
		Restart: pulumi.String("unless-stopped"),
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/etc/caddy/Caddyfile"),
				Source: pulumi.String("Caddyfile"),
			},
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(80),
				External: pulumi.Int(80),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: network.Name,
			},
		},
	})
	if err != nil {
		return err
	}

	return nil
}
