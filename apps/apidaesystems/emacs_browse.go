package main

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const emacsBrowseServiceYAML = `    - Browse:
        href: https://emacs.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://emacs.{{HOMEPAGE_VAR_DOMAIN}}
        icon: emacs.svg
        server: local
        container: emacs-browse
`

// createEmacsBrowse provisions a public read-only Doom Emacs viewer
// served via ttyd. Visitors land in a fresh emacs session pointed at
// /repo/README.org. The container is the security boundary: read-only
// rootfs, no capabilities, ephemeral home tmpfs, repo mounted RO from
// the host. The elisp lockdowns in config.el are belt-and-suspenders.
func createEmacsBrowse(ctx *pulumi.Context, proxyNetwork *docker.Network, domain string, settings serviceConfig) error {
	const imageTag = "apidae-systems-emacs-browse:latest"

	buildImage, err := local.NewCommand(ctx, "emacs-browse-image-build", &local.CommandArgs{
		Create: pulumi.String("docker build -t " + imageTag + " ./docker/emacs-browse/"),
		Update: pulumi.String("docker build -t " + imageTag + " ./docker/emacs-browse/"),
		Delete: pulumi.Sprintf("docker rmi %s || true", imageTag),
	})
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "emacs-browse", &docker.ContainerArgs{
		Image:               pulumi.String(imageTag),
		Name:                pulumi.String("emacs-browse"),
		Hostname:            pulumi.String("emacs-browse"),
		Restart:             pulumi.String("unless-stopped"),
		ReadOnly:            pulumi.Bool(true),
		Init:                pulumi.Bool(true),
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
		Tmpfs: pulumi.StringMap{
			"/tmp":         pulumi.String("size=16m,nosuid,nodev"),
			"/home/browse": pulumi.String("size=128m,nosuid,nodev,uid=1000,gid=1000"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String(monorepoRoot()),
				ContainerPath: pulumi.String("/repo"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
		Labels: createTraefikLabels("emacs-browse", "emacs."+domain, "7681"),
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("curl -sf -o /dev/null http://127.0.0.1:7681/ || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("60s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{buildImage}))
	if err != nil {
		return err
	}

	ctx.Export("emacs-browse id", container.ID())
	return nil
}
