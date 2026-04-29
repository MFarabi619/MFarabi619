package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const homeAssistantServiceYAML = `    - Home Assistant:
        href: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        icon: home-assistant.svg
        server: local
        container: homeassistant
        widget:
          type: homeassistant
          url: http://homeassistant:8123
          key: "{{HOMEPAGE_VAR_HA_ACCESS_TOKEN}}"
`

func createHomeAssistant(ctx *pulumi.Context, proxyNetwork *docker.Network) (*docker.Container, *docker.RemoteImage, *docker.Volume, error) {
	config, err := docker.NewVolume(ctx, "homeassistant-config", &docker.VolumeArgs{
		Name: pulumi.String("homeassistant-config"),
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

	image, err := docker.NewRemoteImage(ctx, "homeassistant", &docker.RemoteImageArgs{
		Name:        pulumi.String("ghcr.io/home-assistant/home-assistant:stable"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "homeassistant", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("homeassistant"),
		Hostname:            pulumi.String("homeassistant"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
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
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/config/configuration.yaml"),
				Source: pulumi.String("homeassistant/configuration.yaml"),
			},
		},
		Labels: createTraefikLabels("homeassistant", "home-assistant."+domain, "8123"),
		Envs: pulumi.StringArray{
			pulumi.String("TZ=America/Toronto"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    config.Name,
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
		return nil, nil, nil, err
	}

	return container, image, config, nil
}
