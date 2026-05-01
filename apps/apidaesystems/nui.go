package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const nuiServiceYAML = `    - NUI:
        href: https://nui.{{HOMEPAGE_VAR_DOMAIN}}
        icon: /icons/nats.svg
        server: local
        container: nui
`

func createNUI(ctx *pulumi.Context, proxyNetwork *docker.Network, domain string, settings serviceConfig) error {
	data, err := createVolume(ctx, "nui-data")
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "nui", settings.Image)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "nui", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("nui"),
		Hostname:            pulumi.String("nui"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(256),
		DestroyGraceSeconds: pulumi.Int(10),
		LogDriver:           pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Labels: createTraefikLabels("nui", "nui."+domain, "31311"),
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:    pulumi.String("/clicontexts/local.json"),
				Content: pulumi.String(`{"description":"Local NATS","url":"nats://nats:4222"}`),
			},
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/db"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return err
	}

	ctx.Export("nui image", image.RepoDigest)
	ctx.Export("nui id", container.ID())
	ctx.Export("nui data", data.Mountpoint)

	return nil
}
