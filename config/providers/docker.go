// https://www.pulumi.com/registry/packages/docker/
package providers

import (
	"github.com/pulumi/pulumi-docker/sdk/v4/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func ProvisionDockerContainers(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}

	image, err := docker.NewRemoteImage(ctx, "excalidraw", &docker.RemoteImageArgs{
		Name: pulumi.String("excalidraw/excalidraw:latest"),
	})

	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "excalidraw", &docker.ContainerArgs{
		Image:      image.ImageId,
		Start:      pulumi.Bool(true),
		MustRun:    pulumi.Bool(true),
		Name:       pulumi.String("excalidraw"),
		WorkingDir: pulumi.String("/var/lib/excalidraw"),

		//	Command: pulumi.StringArray{
		//	pulumi.String("string"),
		//	},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				External: pulumi.Int(5000),
				Internal: pulumi.Int(80),
			},
		},
	})

	if err != nil {
		return err
	}

	image, err = docker.NewRemoteImage(ctx, "open-webui", &docker.RemoteImageArgs{
		Name: pulumi.String("ghcr.io/open-webui/open-webui:main"),
	})

	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "open-webui", &docker.ContainerArgs{
		Image:   image.ImageId,
		Start:   pulumi.Bool(true),
		MustRun: pulumi.Bool(true),
		Name:    pulumi.String("open-webui"),
		Envs: pulumi.StringArray{
			pulumi.String("WEBUI_AUTH=False"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    pulumi.String("open-webui"),
				ContainerPath: pulumi.String("/app/backend/data"),
			},
		},

		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				External: pulumi.Int(3000),
				Internal: pulumi.Int(8080),
			},
		},
	})

	if err != nil {
		return err
	}

	return nil
}
