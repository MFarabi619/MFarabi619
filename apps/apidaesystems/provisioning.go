package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createVolume(ctx *pulumi.Context, name string) (*docker.Volume, error) {
	return docker.NewVolume(ctx, name, &docker.VolumeArgs{
		Name: pulumi.String(name),
		Labels: docker.VolumeLabelArray{
			&docker.VolumeLabelArgs{
				Label: pulumi.String("managed-by"),
				Value: pulumi.String("pulumi"),
			},
		},
	}, pulumi.Protect(true))
}

func pullImage(ctx *pulumi.Context, name, image string) (*docker.RemoteImage, error) {
	return docker.NewRemoteImage(ctx, name, &docker.RemoteImageArgs{
		Name:        pulumi.String(image),
		KeepLocally: pulumi.Bool(true),
	})
}
