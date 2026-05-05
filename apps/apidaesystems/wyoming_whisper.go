package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createWyomingWhisper(ctx *pulumi.Context, proxyNetwork *docker.Network, settings serviceConfig, model string) (*docker.Container, error) {
	data, err := createVolume(ctx, "wyoming-whisper-data")
	if err != nil {
		return nil, err
	}

	image, err := pullImage(ctx, "wyoming-whisper", settings.Image)
	if err != nil {
		return nil, err
	}

	container, err := docker.NewContainer(ctx, "wyoming-whisper", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("wyoming-whisper"),
		Hostname:            pulumi.String("wyoming-whisper"),
		Restart:             pulumi.String("unless-stopped"),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(300),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(512),
		DestroyGraceSeconds: pulumi.Int(10),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
			Adds: pulumi.StringArray{
				pulumi.String("CHOWN"),
				pulumi.String("SETUID"),
				pulumi.String("SETGID"),
				pulumi.String("DAC_OVERRIDE"),
				pulumi.String("FOWNER"),
			},
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Envs: pulumi.StringArray{
			pulumi.String("PUID=1000"),
			pulumi.String("PGID=1000"),
			pulumi.String("TZ=America/Toronto"),
		},
		Init: pulumi.Bool(true),
		Command: pulumi.StringArray{
			pulumi.String("--model"),
			pulumi.String(model),
			pulumi.String("--language"),
			pulumi.String("en"),
			pulumi.String("--beam-size"),
			pulumi.String("1"),
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("python3 -c \"import socket; sock = socket.socket(); sock.settimeout(3); sock.connect(('localhost', 10300)); sock.close()\""),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("180s"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/config"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return nil, err
	}

	ctx.Export("wyoming-whisper image", image.RepoDigest)
	ctx.Export("wyoming-whisper id", container.ID())
	ctx.Export("wyoming-whisper data", data.Mountpoint)

	return container, nil
}
