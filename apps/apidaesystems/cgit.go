package main

import (
	"os/exec"
	"strings"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const cgitServiceYAML = `    - Source:
        href: https://git.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://git.{{HOMEPAGE_VAR_DOMAIN}}
        icon: git.svg
        server: local
        container: cgit
`

func createCgit(ctx *pulumi.Context, proxyNetwork *docker.Network, domain string, settings serviceConfig) error {
	gitRepos, err := createVolume(ctx, "git-repos")
	if err != nil {
		return err
	}

	gitCache, err := docker.NewVolume(ctx, "git-cache", &docker.VolumeArgs{
		Name: pulumi.String("git-cache"),
		Labels: docker.VolumeLabelArray{
			&docker.VolumeLabelArgs{
				Label: pulumi.String("managed-by"),
				Value: pulumi.String("pulumi"),
			},
		},
	})
	if err != nil {
		return err
	}

	seedRepos, err := local.NewCommand(ctx, "cgit-seed-repos", &local.CommandArgs{
		Create: pulumi.Sprintf(`docker run --rm --entrypoint sh -v %s:/srv/git -v "$(git -C ../../ rev-parse --show-toplevel)":/src:ro alpine/git -c 'test -d /srv/git/MFarabi619.git || git clone --mirror /src /srv/git/MFarabi619.git'`, gitRepos.Name),
	}, pulumi.DependsOn([]pulumi.Resource{gitRepos}))
	if err != nil {
		return err
	}

	hostRepoOut, err := exec.Command("git", "-C", "../../", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return err
	}
	hostRepoPath := strings.TrimSpace(string(hostRepoOut))

	fetchImage, err := pullImage(ctx, "cgit-fetch", "alpine/git:latest")
	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "cgit-fetch", &docker.ContainerArgs{
		Image:    fetchImage.ImageId,
		Name:     pulumi.String("cgit-fetch"),
		Hostname: pulumi.String("cgit-fetch"),
		Restart:  pulumi.String("unless-stopped"),
		Memory:   pulumi.Int(32),
		Entrypoints: pulumi.StringArray{
			pulumi.String("sh"),
			pulumi.String("-c"),
		},
		Command: pulumi.StringArray{
			pulumi.String(`while true; do git -C /srv/git/MFarabi619.git remote update --prune || true; sleep 300; done`),
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    gitRepos.Name,
				ContainerPath: pulumi.String("/srv/git"),
			},
			&docker.ContainerVolumeArgs{
				HostPath:      pulumi.String(hostRepoPath),
				ContainerPath: pulumi.String("/src"),
				ReadOnly:      pulumi.Bool(true),
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{seedRepos}))
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "cgit", settings.Image)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "cgit", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("cgit"),
		Hostname:            pulumi.String("cgit"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(256),
		DestroyGraceSeconds: pulumi.Int(10),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
			Adds: pulumi.StringArray{
				pulumi.String("CHOWN"),
				pulumi.String("SETUID"),
				pulumi.String("SETGID"),
				pulumi.String("DAC_OVERRIDE"),
				pulumi.String("FOWNER"),
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
			pulumi.String("CGIT_TITLE=" + domain),
			pulumi.String("CGIT_DESC=source code"),
			pulumi.String("CGIT_ENABLE_HTTP_CLONE=1"),
			pulumi.String("CGIT_SNAPSHOTS=tar.gz zip"),
		},
		Labels: createTraefikLabels("cgit", "git."+domain, "80"),
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    gitRepos.Name,
				ContainerPath: pulumi.String("/srv/git"),
				ReadOnly:      pulumi.Bool(true),
			},
			&docker.ContainerVolumeArgs{
				VolumeName:    gitCache.Name,
				ContainerPath: pulumi.String("/var/cache/cgit"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget -q --spider http://127.0.0.1:80/ || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("10s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{seedRepos}))
	if err != nil {
		return err
	}

	ctx.Export("cgit image", image.RepoDigest)
	ctx.Export("cgit id", container.ID())
	ctx.Export("git repos", gitRepos.Mountpoint)

	return nil
}
