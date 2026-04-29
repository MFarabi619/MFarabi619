package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createTraefikLabels(name, host, port string) docker.ContainerLabelArray {
	return docker.ContainerLabelArray{
		&docker.ContainerLabelArgs{
			Label: pulumi.String("traefik.enable"),
			Value: pulumi.String("true"),
		},
		&docker.ContainerLabelArgs{
			Label: pulumi.String("traefik.docker.network"),
			Value: pulumi.String("proxy"),
		},
		&docker.ContainerLabelArgs{
			Label: pulumi.String("traefik.http.routers." + name + ".rule"),
			Value: pulumi.String("Host(`" + host + "`)"),
		},
		&docker.ContainerLabelArgs{
			Label: pulumi.String("traefik.http.routers." + name + ".entrypoints"),
			Value: pulumi.String("web"),
		},
		&docker.ContainerLabelArgs{
			Label: pulumi.String("traefik.http.services." + name + ".loadbalancer.server.port"),
			Value: pulumi.String(port),
		},
	}
}

func createTraefik(ctx *pulumi.Context, proxyNetwork *docker.Network) (*docker.Container, *docker.RemoteImage, error) {
	image, err := docker.NewRemoteImage(ctx, "traefik", &docker.RemoteImageArgs{
		Name:        pulumi.String("traefik:v3.4"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "traefik", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("traefik"),
		Hostname:            pulumi.String("traefik"),
		Init:                pulumi.Bool(true),
		ReadOnly:            pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(60),
		Memory:              pulumi.Int(128),
		MemorySwap:          pulumi.Int(128),
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
		Command: pulumi.StringArray{
			pulumi.String("--providers.docker=true"),
			pulumi.String("--providers.docker.exposedbydefault=false"),
			pulumi.String("--providers.docker.network=proxy"),
			pulumi.String("--entrypoints.web.address=:80"),
			pulumi.String("--ping=true"),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(80),
				External: pulumi.Int(80),
			},
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String("/var/run/docker.sock"),
				ContainerPath: pulumi.String("/var/run/docker.sock"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests:       pulumi.StringArray{pulumi.String("CMD"), pulumi.String("traefik"), pulumi.String("healthcheck"), pulumi.String("--ping")},
			Interval:    pulumi.String("10s"),
			Timeout:     pulumi.String("3s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("5s"),
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
