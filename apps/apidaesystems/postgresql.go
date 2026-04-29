package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createPostgreSQL(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string) (*docker.Container, *docker.RemoteImage, *docker.Volume, error) {
	data, err := docker.NewVolume(ctx, "postgresql-data", &docker.VolumeArgs{
		Name: pulumi.String("postgresql-data"),
		Labels: docker.VolumeLabelArray{
			&docker.VolumeLabelArgs{
				Label: pulumi.String("managed-by"),
				Value: pulumi.String("pulumi"),
			},
		},
	})
	if err != nil {
		return nil, nil, nil, err
	}

	image, err := docker.NewRemoteImage(ctx, "postgresql", &docker.RemoteImageArgs{
		Name:        pulumi.String("postgres:18-alpine"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "postgresql", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("postgresql"),
		Hostname:            pulumi.String("postgresql"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(120),
		Memory:              pulumi.Int(512),
		MemorySwap:          pulumi.Int(512),
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
			pulumi.String("POSTGRES_DB=authentik"),
			pulumi.String("POSTGRES_USER=authentik"),
			pulumi.String("POSTGRES_PASSWORD=" + secrets["AUTHENTIK_PG_PASSWORD"]),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/var/lib/postgresql/data"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("pg_isready -U authentik"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("10s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("20s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return nil, nil, nil, err
	}

	return container, image, data, nil
}
