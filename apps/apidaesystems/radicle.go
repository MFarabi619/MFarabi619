package main

// DISABLED 2026-04-29: nix-darwin linux-builder VM cannot execute bash
// ("/nix/store/...-bash-5.3p9/bin/bash: Undefined error: 0").
// The VM is non-ephemeral and its store drifted from nixpkgs — the bash
// binary referenced by new derivations doesn't exist in the VM.
// Fix: darwin-rebuild switch to recreate the VM, then re-enable.
// Nix flake at apps/apidaesystems/docker/radicle/flake.nix is ready (uses writeTextFile
// entrypoint with rad config init, radicle-explorer.withConfig for
// build-time seed config, s6 process supervision).
// Re-enable by swapping cgit back to radicle in main.go and Pulumi.yaml.

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const radicleServiceYAML = `    - Radicle:
        href: https://git.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://git.{{HOMEPAGE_VAR_DOMAIN}}
        description: Decentralized Code Hosting
        icon: /icons/radicle.svg
        server: local
        container: radicle
`

func createRadicle(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, domain string, settings serviceConfig) error {
	data, err := createVolume(ctx, "radicle-data")
	if err != nil {
		return err
	}

	const imageTag = "apidae-systems-radicle:latest"

	buildImage, err := local.NewCommand(ctx, "radicle-image-build", &local.CommandArgs{
		Create: pulumi.String("nix build path:./docker/radicle#default --system aarch64-linux --no-link --print-out-paths | xargs docker load -i"),
		Delete: pulumi.Sprintf("docker rmi %s || true", imageTag),
	})
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "radicle", &docker.ContainerArgs{
		Image:               pulumi.String(imageTag),
		Name:                pulumi.String("radicle"),
		Hostname:            pulumi.String("radicle"),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
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
		Envs: pulumi.StringArray{
			pulumi.String("RAD_HOME=/data"),
			pulumi.String("RAD_PASSPHRASE=" + secrets["RAD_PASSPHRASE"]),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(8776),
				External: pulumi.Int(8776),
			},
		},
		Labels: createTraefikLabels("radicle", "git."+domain, "3000"),
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/data"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget -q --spider http://localhost:8080/api/v1 || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("30s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{buildImage}), pulumi.AdditionalSecretOutputs([]string{"envs"}))
	if err != nil {
		return err
	}

	ctx.Export("radicle id", container.ID())
	ctx.Export("radicle data", data.Mountpoint)

	return nil
}
