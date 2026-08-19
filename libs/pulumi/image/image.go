package image

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func Pull(ctx *pulumi.Context, name, ref string) (*docker.RemoteImage, error) {
	return docker.NewRemoteImage(ctx, name, &docker.RemoteImageArgs{
		Name:        pulumi.String(ref),
		KeepLocally: pulumi.Bool(true),
	})
}
