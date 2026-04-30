package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

const homeAssistantServiceYAML = `    - Home Assistant:
        href: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        icon: home-assistant.svg
        server: local
        container: home-assistant
        widget:
          type: homeassistant
          url: http://home-assistant:8123
          key: "{{HOMEPAGE_VAR_HA_ACCESS_TOKEN}}"
`

func createHomeAssistant(ctx *pulumi.Context, proxyNetwork *docker.Network, domain string, settings serviceConfig) error {
	homeAssistantConfig, err := createVolume(ctx, "home-assistant-config")
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "home-assistant", settings.Image)
	if err != nil {
		return err
	}

	configuration := map[string]any{
		"default_config": nil,
		"homeassistant": map[string]any{
			"name":        "Apidae Systems",
			"latitude":    43.6532,
			"longitude":   -79.3832,
			"elevation":   76,
			"unit_system": "metric",
			"time_zone":   "America/Toronto",
			"country":     "CA",
			"language":    "en",
			"currency":    "CAD",
		},
		"http": map[string]any{
			"use_x_forwarded_for": true,
			"trusted_proxies":     []string{"172.18.0.0/16"},
		},
		"recorder": map[string]any{
			"auto_purge":      true,
			"purge_keep_days": 10,
		},
		"history": nil,
	}
	configYAML, err := yaml.Marshal(configuration)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "home-assistant", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("home-assistant"),
		Hostname:            pulumi.String("home-assistant"),
		Restart:             pulumi.String("unless-stopped"),
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
				pulumi.String("NET_RAW"),
			},
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:    pulumi.String("/config/configuration.yaml"),
				Content: pulumi.String(string(configYAML)),
			},
		},
		Labels: createTraefikLabels("home-assistant", "home-assistant."+domain, "8123"),
		Envs: pulumi.StringArray{
			pulumi.String("TZ=America/Toronto"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    homeAssistantConfig.Name,
				ContainerPath: pulumi.String("/config"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget --no-verbose --tries=1 --spider http://localhost:8123 || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("30s"),
		},
	})
	if err != nil {
		return err
	}

	ctx.Export("home-assistant image", image.RepoDigest)
	ctx.Export("home-assistant id", container.ID())
	ctx.Export("home-assistant config", homeAssistantConfig.Mountpoint)

	return nil
}
