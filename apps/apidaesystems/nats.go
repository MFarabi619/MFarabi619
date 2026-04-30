package main

import (
	"fmt"

	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func natsServerConfig(mqttPassword string) string {
	return fmt.Sprintf(`port: 4222
server_name: apidae-systems

jetstream {
    store_dir: /data/jetstream
}

mqtt {
    port: 1883
    authorization {
        username: "mfarabi"
        password: "%s"
    }
}

http_port: 8222
`, mqttPassword)
}

const natsServiceYAML = `    - NATS:
        icon: /icons/nats.svg
        server: local
        container: nats
`

func createNATS(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, settings serviceConfig) (*docker.Container, error) {
	data, err := createVolume(ctx, "nats-data")
	if err != nil {
		return nil, err
	}

	image, err := pullImage(ctx, "nats", settings.Image)
	if err != nil {
		return nil, err
	}

	container, err := docker.NewContainer(ctx, "nats", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("nats"),
		Hostname:            pulumi.String("nats"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(256),
		DestroyGraceSeconds: pulumi.Int(10),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(60),
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
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(1883),
				External: pulumi.Int(1883),
			},
		},
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:    pulumi.String("/etc/nats/nats-server.conf"),
				Content: pulumi.String(natsServerConfig(secrets["NATS_MQTT_PASSWORD"])),
			},
		},
		Command: pulumi.StringArray{
			pulumi.String("--config"),
			pulumi.String("/etc/nats/nats-server.conf"),
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget --no-verbose --tries=1 --spider http://localhost:8222/healthz || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("10s"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/data"),
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

	ctx.Export("nats image", image.RepoDigest)
	ctx.Export("nats id", container.ID())
	ctx.Export("nats data", data.Mountpoint)

	return container, nil
}
