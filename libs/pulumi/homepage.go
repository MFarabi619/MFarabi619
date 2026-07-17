package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createHomepage(ctx *pulumi.Context, network *docker.Network) error {
	image, err := pullImage(ctx, "homepage", "ghcr.io/gethomepage/homepage:latest")
	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "homepage", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("homepage"),
		Hostname:            pulumi.String("homepage"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(256),
		MemorySwap:          pulumi.Int(256),
		MemoryReservation:   pulumi.Int(192),
		CpuShares:           pulumi.Int(256),
		DestroyGraceSeconds: pulumi.Int(10),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
		},
		SecurityOpts: pulumi.StringArray{
			pulumi.String("no-new-privileges:true"),
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Envs: pulumi.StringArray{
			pulumi.String("HOMEPAGE_ALLOWED_HOSTS=localhost:3000"),
		},
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/config/settings.yaml"),
				Source: pulumi.String("homepage-dashboard/settings.yaml"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/config/widgets.yaml"),
				Source: pulumi.String("homepage-dashboard/widgets.yaml"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/config/bookmarks.yaml"),
				Source: pulumi.String("homepage-dashboard/bookmarks.yaml"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/config/docker.yaml"),
				Source: pulumi.String("homepage-dashboard/docker.yaml"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/config/custom.css"),
				Source: pulumi.String("homepage-dashboard/custom.css"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/public/images/tandem-robotics-banner-bg.png"),
				Source: pulumi.String("../../apps/robot/assets/public/tandem-robotics-banner-bg.png"),
			},
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String("/var/run/docker.sock"),
				ContainerPath: pulumi.String("/var/run/docker.sock"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(3000),
				External: pulumi.Int(3000),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: network.Name,
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("10s"),
		},
	})
	if err != nil {
		return err
	}

	return nil
}
