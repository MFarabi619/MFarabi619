package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createMailpit(ctx *pulumi.Context) error {
	credential, err := decryptSecret("MP_SEND_API_AUTH")
	if err != nil {
		return err
	}

	image, err := docker.NewRemoteImage(ctx, "mailpit", &docker.RemoteImageArgs{
		Name:        pulumi.String("axllent/mailpit:latest"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "mailpit", &docker.ContainerArgs{
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
	})
	if err != nil {
		return err
	}

	ctx.Export("mailpit id", container.ID())

	return nil
}
