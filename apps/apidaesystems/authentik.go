package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const authentikServiceYAML = `    - Authentik:
        href: https://auth.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://auth.{{HOMEPAGE_VAR_DOMAIN}}
        icon: authentik.svg
        server: local
        container: authentik-server
        widget:
          type: authentik
          url: http://authentik-server:9000
          key: "{{HOMEPAGE_VAR_AUTHENTIK_API_TOKEN}}"
`

func createAuthentikEnvs(secrets map[string]string) pulumi.StringArray {
	return pulumi.StringArray{
		pulumi.String("AUTHENTIK_SECRET_KEY=" + secrets["AUTHENTIK_SECRET_KEY"]),
		pulumi.String("AUTHENTIK_POSTGRESQL__HOST=postgresql"),
		pulumi.String("AUTHENTIK_POSTGRESQL__PORT=5432"),
		pulumi.String("AUTHENTIK_POSTGRESQL__USER=authentik"),
		pulumi.String("AUTHENTIK_POSTGRESQL__NAME=authentik"),
		pulumi.String("AUTHENTIK_POSTGRESQL__PASSWORD=" + secrets["AUTHENTIK_PG_PASSWORD"]),
		pulumi.String("AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=0.0.0.0/0,::/0"),
	}
}

func createAuthentikServer(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, domain string, postgresql *docker.Container, settings serviceConfig) (*docker.RemoteImage, *docker.Volume, error) {
	media, err := createVolume(ctx, "authentik-media")
	if err != nil {
		return nil, nil, err
	}

	image, err := pullImage(ctx, "authentik", settings.Image)
	if err != nil {
		return nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "authentik-server", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("authentik-server"),
		Hostname:            pulumi.String("authentik-server"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		ShmSize:             pulumi.Int(512),
		CpuShares:           pulumi.Int(512),
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
			pulumi.String("server"),
		},
		Labels: createTraefikLabels("authentik", "auth."+domain, "9000"),
		Envs:   createAuthentikEnvs(secrets),
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    media.Name,
				ContainerPath: pulumi.String("/media"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD"),
				pulumi.String("curl"),
				pulumi.String("-f"),
				pulumi.String("http://localhost:9000/-/health/live/"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("20s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{postgresql}), pulumi.AdditionalSecretOutputs([]string{"envs"}))
	if err != nil {
		return nil, nil, err
	}

	ctx.Export("authentik image", image.RepoDigest)
	ctx.Export("authentik server id", container.ID())
	ctx.Export("authentik media", media.Mountpoint)

	return image, media, nil
}

func createAuthentikWorker(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, image *docker.RemoteImage, media *docker.Volume, postgresql *docker.Container, settings serviceConfig) error {
	container, err := docker.NewContainer(ctx, "authentik-worker", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("authentik-worker"),
		Hostname:            pulumi.String("authentik-worker"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		ShmSize:             pulumi.Int(512),
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
		Command: pulumi.StringArray{
			pulumi.String("worker"),
		},
		Envs: createAuthentikEnvs(secrets),
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    media.Name,
				ContainerPath: pulumi.String("/media"),
			},
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String("/var/run/docker.sock"),
				ContainerPath: pulumi.String("/var/run/docker.sock"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD"),
				pulumi.String("ak"),
				pulumi.String("healthcheck"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("20s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{postgresql}), pulumi.AdditionalSecretOutputs([]string{"envs"}))
	if err != nil {
		return err
	}

	ctx.Export("authentik worker id", container.ID())

	return nil
}
