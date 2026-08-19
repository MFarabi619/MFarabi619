package service

import (
	"embed"

	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"libs/pulumi/image"
)

//go:embed homepage-dashboard
var homepageAssets embed.FS

func Homepage(ctx *pulumi.Context, network *docker.Network, servicesYAML string) error {
	img, err := image.Pull(ctx, "homepage", "ghcr.io/gethomepage/homepage:latest")
	if err != nil {
		return err
	}

	uploads := docker.ContainerUploadArray{
		&docker.ContainerUploadArgs{
			File:    pulumi.String("/app/config/services.yaml"),
			Content: pulumi.String(servicesYAML),
		},
	}
	assets := []struct {
		file  string
		asset string
	}{
		{"/app/config/settings.yaml", "homepage-dashboard/settings.yaml"},
		{"/app/config/widgets.yaml", "homepage-dashboard/widgets.yaml"},
		{"/app/config/bookmarks.yaml", "homepage-dashboard/bookmarks.yaml"},
		{"/app/config/docker.yaml", "homepage-dashboard/docker.yaml"},
		{"/app/config/custom.css", "homepage-dashboard/custom.css"},
	}
	for _, entry := range assets {
		content, err := homepageAssets.ReadFile(entry.asset)
		if err != nil {
			return err
		}
		uploads = append(uploads, &docker.ContainerUploadArgs{
			File:    pulumi.String(entry.file),
			Content: pulumi.String(string(content)),
		})
	}

	_, err = docker.NewContainer(ctx, "homepage", &docker.ContainerArgs{
		Image:               img.ImageId,
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
			pulumi.String("HOMEPAGE_ALLOWED_HOSTS=localhost,localhost:3000"),
		},
		Uploads: uploads,
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

	return err
}
