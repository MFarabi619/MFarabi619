package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createMosquitto(ctx *pulumi.Context, proxyNetwork *docker.Network) (*docker.Container, *docker.RemoteImage, error) {
	data, err := docker.NewVolume(ctx, "mosquitto-data", &docker.VolumeArgs{
		Name: pulumi.String("mosquitto-data"),
		Labels: docker.VolumeLabelArray{
			&docker.VolumeLabelArgs{
				Label: pulumi.String("managed-by"),
				Value: pulumi.String("pulumi"),
			},
		},
	})
	if err != nil {
		return nil, nil, err
	}

	image, err := docker.NewRemoteImage(ctx, "mosquitto", &docker.RemoteImageArgs{
		Name:        pulumi.String("eclipse-mosquitto:latest"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "mosquitto", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("mosquitto"),
		Hostname:            pulumi.String("mosquitto"),
		User:                pulumi.String("1883:1883"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(64),
		MemorySwap:          pulumi.Int(64),
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
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/mosquitto/config/mosquitto.conf"),
				Source: pulumi.String("mosquitto/mosquitto.conf"),
			},
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/mosquitto/data"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return nil, nil, err
	}

	return container, image, nil
}
