package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func pullImage(ctx *pulumi.Context, name, image string) (*docker.RemoteImage, error) {
	return docker.NewRemoteImage(ctx, name, &docker.RemoteImageArgs{
		Name:        pulumi.String(image),
		KeepLocally: pulumi.Bool(true),
	})
}
