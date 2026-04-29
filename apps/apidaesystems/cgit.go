package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createCgit(ctx *pulumi.Context, proxyNetwork *docker.Network) (*docker.Container, *docker.RemoteImage, *docker.Volume, error) {
	gitRepos, err := docker.NewVolume(ctx, "git-repos", &docker.VolumeArgs{
		Name: pulumi.String("git-repos"),
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
		return nil, nil, nil, err
	}

	image, err := docker.NewRemoteImage(ctx, "cgit", &docker.RemoteImageArgs{
		Name:        pulumi.String("joseluisq/alpine-cgit:2"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, nil, err
	}

	container, err := docker.NewContainer(ctx, "cgit", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("cgit"),
		Hostname:            pulumi.String("cgit"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(128),
		MemorySwap:          pulumi.Int(128),
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
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return nil, nil, nil, err
	}

	return container, image, gitRepos, nil
}
