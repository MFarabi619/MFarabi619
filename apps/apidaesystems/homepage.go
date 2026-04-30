package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const calendarServiceYAML = `    - Calendar:
        widget:
          type: calendar
          view: monthly
          maxEvents: 10
          showTime: true
          timezone: America/Toronto
          firstDayInWeek: monday
`

func createHomepage(ctx *pulumi.Context, proxyNetwork *docker.Network, servicesYAML string, envs pulumi.StringArray, domain string, settings serviceConfig) error {
	image, err := pullImage(ctx, "homepage", settings.Image)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "homepage", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("homepage"),
		Hostname:            pulumi.String("homepage"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
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
		Labels: docker.ContainerLabelArray{
			&docker.ContainerLabelArgs{
				Label: pulumi.String("traefik.enable"),
				Value: pulumi.String("true"),
			},
			&docker.ContainerLabelArgs{
				Label: pulumi.String("traefik.docker.network"),
				Value: pulumi.String("proxy"),
			},
			&docker.ContainerLabelArgs{
				Label: pulumi.String("traefik.http.routers.homepage.rule"),
				Value: pulumi.String("Host(`" + domain + "`) || Host(`www." + domain + "`)"),
			},
			&docker.ContainerLabelArgs{
				Label: pulumi.String("traefik.http.routers.homepage.entrypoints"),
				Value: pulumi.String("web"),
			},
			&docker.ContainerLabelArgs{
				Label: pulumi.String("traefik.http.services.homepage.loadbalancer.server.port"),
				Value: pulumi.String("3000"),
			},
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
				File:    pulumi.String("/app/config/services.yaml"),
				Content: pulumi.String(servicesYAML),
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
				File:   pulumi.String("/app/public/icons/symbol.svg"),
				Source: pulumi.String("../../web/assets/symbol.svg"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/public/images/apidae-systems-banner-bg.png"),
				Source: pulumi.String("../../assets/apidae-systems-banner-bg.png"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/public/icons/radicle.svg"),
				Source: pulumi.String("../../assets/icons/radicle.svg"),
			},
			&docker.ContainerUploadArgs{
				File:   pulumi.String("/app/public/icons/nats.svg"),
				Source: pulumi.String("../../assets/icons/nats.svg"),
			},
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String("/var/run/docker.sock"),
				ContainerPath: pulumi.String("/var/run/docker.sock"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
		Envs: envs,
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
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
	}, pulumi.AdditionalSecretOutputs([]string{"envs"}))
	if err != nil {
		return err
	}

	ctx.Export("homepage image", image.RepoDigest)
	ctx.Export("homepage id", container.ID())

	return nil
}
