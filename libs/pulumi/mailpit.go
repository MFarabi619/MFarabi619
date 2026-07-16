package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createMailpit(ctx *pulumi.Context, network *docker.Network) error {
	credential, err := decryptSecret("MP_SEND_API_AUTH")
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "mailpit", "axllent/mailpit:latest")
	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "mailpit", &docker.ContainerArgs{
		Image:   image.ImageId,
		Name:    pulumi.String("mailpit"),
		Restart: pulumi.String("unless-stopped"),
		Envs: pulumi.StringArray{
			pulumi.Sprintf("MP_SEND_API_AUTH=%s", credential),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(1025),
				External: pulumi.Int(1025),
			},
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(8025),
				External: pulumi.Int(8025),
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
