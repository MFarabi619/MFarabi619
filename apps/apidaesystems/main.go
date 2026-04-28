package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		proxyNetwork, err := docker.NewNetwork(ctx, "proxy", &docker.NetworkArgs{
			Name: pulumi.String("proxy"),
			Labels: docker.NetworkLabelArray{
				&docker.NetworkLabelArgs{
					Label: pulumi.String("managed-by"),
					Value: pulumi.String("pulumi"),
				},
			},
		})
		if err != nil {
			return err
		}

		traefikImage, err := docker.NewRemoteImage(ctx, "traefik", &docker.RemoteImageArgs{
			Name:        pulumi.String("traefik:v3.4"),
			KeepLocally: pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		traefik, err := docker.NewContainer(ctx, "traefik", &docker.ContainerArgs{
			Image:               traefikImage.ImageId,
			Name:                pulumi.String("traefik"),
			Init:                pulumi.Bool(true),
			ReadOnly:            pulumi.Bool(true),
			Restart:             pulumi.String("unless-stopped"),
			Memory:              pulumi.Int(128),
			DestroyGraceSeconds: pulumi.Int(10),
			LogDriver:           pulumi.String("json-file"),
			LogOpts: pulumi.StringMap{
				"max-size": pulumi.String("10m"),
				"max-file": pulumi.String("3"),
			},
			Command: pulumi.StringArray{
				pulumi.String("--providers.docker=true"),
				pulumi.String("--providers.docker.exposedbydefault=false"),
				pulumi.String("--providers.docker.network=proxy"),
				pulumi.String("--entrypoints.web.address=:80"),
				pulumi.String("--ping=true"),
			},
			Ports: docker.ContainerPortArray{
				&docker.ContainerPortArgs{
					Internal: pulumi.Int(80),
					External: pulumi.Int(80),
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
				Tests:       pulumi.StringArray{pulumi.String("CMD"), pulumi.String("traefik"), pulumi.String("healthcheck"), pulumi.String("--ping")},
				Interval:    pulumi.String("10s"),
				Timeout:     pulumi.String("3s"),
				Retries:     pulumi.Int(3),
				StartPeriod: pulumi.String("5s"),
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

		homepageImage, err := docker.NewRemoteImage(ctx, "homepage", &docker.RemoteImageArgs{
			Name:        pulumi.String("ghcr.io/gethomepage/homepage:latest"),
			KeepLocally: pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		homepage, err := docker.NewContainer(ctx, "homepage", &docker.ContainerArgs{
			Image:               homepageImage.ImageId,
			Name:                pulumi.String("homepage"),
			Init:                pulumi.Bool(true),
			Restart:             pulumi.String("unless-stopped"),
			Memory:              pulumi.Int(256),
			DestroyGraceSeconds: pulumi.Int(10),
			LogDriver:           pulumi.String("json-file"),
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
					Label: pulumi.String("traefik.http.routers.homepage.rule"),
					Value: pulumi.String("Host(`apidae.systems`) || Host(`www.apidae.systems`)"),
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
					File:   pulumi.String("/app/config/services.yaml"),
					Source: pulumi.String("homepage-dashboard/services.yaml"),
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
			},
			Volumes: docker.ContainerVolumeArray{
				&docker.ContainerVolumeArgs{
					HostPath:      pulumi.String("/var/run/docker.sock"),
					ContainerPath: pulumi.String("/var/run/docker.sock"),
					ReadOnly:      pulumi.Bool(true),
				},
			},
			Envs: pulumi.StringArray{
				pulumi.String("HOMEPAGE_ALLOWED_HOSTS=apidae.systems,www.apidae.systems"),
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

		cgitImage, err := docker.NewRemoteImage(ctx, "cgit", &docker.RemoteImageArgs{
			Name:        pulumi.String("joseluisq/alpine-cgit:2"),
			KeepLocally: pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		cgit, err := docker.NewContainer(ctx, "cgit", &docker.ContainerArgs{
			Image:               cgitImage.ImageId,
			Name:                pulumi.String("cgit"),
			Init:                pulumi.Bool(true),
			Restart:             pulumi.String("unless-stopped"),
			Memory:              pulumi.Int(128),
			DestroyGraceSeconds: pulumi.Int(10),
			LogDriver:           pulumi.String("json-file"),
			LogOpts: pulumi.StringMap{
				"max-size": pulumi.String("10m"),
				"max-file": pulumi.String("3"),
			},
			Envs: pulumi.StringArray{
				pulumi.String("CGIT_TITLE=apidae.systems"),
				pulumi.String("CGIT_DESC=source code"),
				pulumi.String("CGIT_ENABLE_HTTP_CLONE=1"),
				pulumi.String("CGIT_SNAPSHOTS=tar.gz zip"),
			},
			Labels: docker.ContainerLabelArray{
				&docker.ContainerLabelArgs{
					Label: pulumi.String("traefik.enable"),
					Value: pulumi.String("true"),
				},
				&docker.ContainerLabelArgs{
					Label: pulumi.String("traefik.http.routers.cgit.rule"),
					Value: pulumi.String("Host(`git.apidae.systems`)"),
				},
				&docker.ContainerLabelArgs{
					Label: pulumi.String("traefik.http.routers.cgit.entrypoints"),
					Value: pulumi.String("web"),
				},
				&docker.ContainerLabelArgs{
					Label: pulumi.String("traefik.http.services.cgit.loadbalancer.server.port"),
					Value: pulumi.String("80"),
				},
			},
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
			return err
		}

		ctx.Export("network", proxyNetwork.Name)
		ctx.Export("traefik image", traefikImage.RepoDigest)
		ctx.Export("traefik id", traefik.ID())
		ctx.Export("homepage image", homepageImage.RepoDigest)
		ctx.Export("homepage id", homepage.ID())
		ctx.Export("cgit image", cgitImage.RepoDigest)
		ctx.Export("cgit id", cgit.ID())
		ctx.Export("git repos", gitRepos.Mountpoint)

		return nil
	})
}
