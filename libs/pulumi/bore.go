package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const boreServiceYAML = `    - Bore:
        href: https://github.com/ekzhang/bore
        description: TCP tunnels for everyone
        icon: mdi-tunnel
        server: local
        container: bore
`

const (
	boreControlPort = 7835
	boreMinPort     = 30000
	boreMaxPort     = 30010
)

func createBore(ctx *pulumi.Context, network *docker.Network) error {
	secret, err := decryptSecret("BORE_SECRET")
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "bore", "ekzhang/bore:latest")
	if err != nil {
		return err
	}

	ports := docker.ContainerPortArray{
		&docker.ContainerPortArgs{
			Internal: pulumi.Int(boreControlPort),
			External: pulumi.Int(boreControlPort),
		},
	}
	for p := boreMinPort; p <= boreMaxPort; p++ {
		ports = append(ports, &docker.ContainerPortArgs{
			Internal: pulumi.Int(p),
			External: pulumi.Int(p),
		})
	}

	_, err = docker.NewContainer(ctx, "bore", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("bore"),
		Hostname:            pulumi.String("bore"),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(32),
		MemorySwap:          pulumi.Int(32),
		MemoryReservation:   pulumi.Int(24),
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
			pulumi.String("server"),
			pulumi.String("--secret"),
			pulumi.Sprintf("%s", secret),
			pulumi.String("--min-port"),
			pulumi.Sprintf("%d", boreMinPort),
			pulumi.String("--max-port"),
			pulumi.Sprintf("%d", boreMaxPort),
		},
		Ports: ports,
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: network.Name,
			},
		},
	}, pulumi.AdditionalSecretOutputs([]string{"command"}))
	if err != nil {
		return err
	}

	return nil
}
