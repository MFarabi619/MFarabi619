package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		network, err := docker.NewNetwork(ctx, "proxy", &docker.NetworkArgs{
			Name: pulumi.String("proxy"),
			Labels: docker.NetworkLabelArray{
				&docker.NetworkLabelArgs{
					Label: pulumi.String("managed-by"),
					Value: pulumi.String("pulumi"),
				},
			},
		})
		if err != nil {
			return err
		}

		if err := createMailpit(ctx, network); err != nil {
			return err
		}

		return nil
	})
}
