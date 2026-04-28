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

		homepageConfig, err := docker.NewVolume(ctx, "homepage-config", &docker.VolumeArgs{
			Name: pulumi.String("homepage-config"),
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
			Volumes: docker.ContainerVolumeArray{
				&docker.ContainerVolumeArgs{
					VolumeName:    homepageConfig.Name,
					ContainerPath: pulumi.String("/app/config"),
				},
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

		ctx.Export("network", proxyNetwork.Name)
		ctx.Export("homepage config", homepageConfig.Mountpoint)
		ctx.Export("traefik image", traefikImage.RepoDigest)
		ctx.Export("traefik id", traefik.ID())
		ctx.Export("homepage image", homepageImage.RepoDigest)
		ctx.Export("homepage id", homepage.ID())

		return nil
	})
}
