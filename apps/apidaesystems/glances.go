package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const glancesServiceYAML = `    - CPU Usage:
        widget:
          type: glances
          url: http://glances:61208
          metric: cpu
          version: 4
    - Memory Usage:
        widget:
          type: glances
          url: http://glances:61208
          metric: memory
          version: 4
    - Network Usage:
        widget:
          type: glances
          url: http://glances:61208
          metric: network:eth0
          version: 4
    - Disk Usage:
        widget:
          type: glances
          url: http://glances:61208
          metric: fs:/etc/hostname
          version: 4
    - Top Processes:
        widget:
          type: glances
          url: http://glances:61208
          metric: process
          version: 4
    # CPU Temp - sensor:cpu_thermal 1 not available on macOS/OrbStack Docker host
    # - CPU Temp:
    #     widget:
    #       type: glances
    #       url: http://glances:61208
    #       metric: sensor:cpu_thermal 1
    #       version: 4
    # Disk I/O - disk:sda device not present on macOS/OrbStack Docker host
    # - Disk I/O:
    #     widget:
    #       type: glances
    #       url: http://glances:61208
    #       metric: disk:sda
    #       version: 4
`

const glancesConfig = `[outputs]
cors_origin=http://homepage:3000
webui_allowed_hosts=glances,localhost,127.0.0.1
`

func createGlances(ctx *pulumi.Context, proxyNetwork *docker.Network, settings serviceConfig) error {
	image, err := pullImage(ctx, "glances", settings.Image)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "glances", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("glances"),
		Hostname:            pulumi.String("glances"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(256),
		DestroyGraceSeconds: pulumi.Int(10),
		PidMode:             pulumi.String("host"),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
			Adds: pulumi.StringArray{
				pulumi.String("SYS_PTRACE"),
			},
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
			pulumi.String("GLANCES_OPT=-w -C /etc/glances/glances.conf"),
			pulumi.String("TZ=America/Toronto"),
		},
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:    pulumi.String("/etc/glances/glances.conf"),
				Content: pulumi.String(glancesConfig),
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
			Tests: pulumi.StringArray{
				pulumi.String("CMD"),
				pulumi.String("wget"),
				pulumi.String("--no-verbose"),
				pulumi.String("--tries=1"),
				pulumi.String("--spider"),
				pulumi.String("http://localhost:61208/api/4/now"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("15s"),
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

	ctx.Export("glances image", image.RepoDigest)
	ctx.Export("glances id", container.ID())

	return nil
}
