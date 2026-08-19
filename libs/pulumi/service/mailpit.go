package service

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"libs/pulumi/image"
	"libs/pulumi/secret"
)

const MailpitYAML = `    - Mailpit:
        href: http://localhost:8025
        icon: mdi-email-outline
        server: local
        container: mailpit
`

func Mailpit(ctx *pulumi.Context, network *docker.Network) error {
	credential, err := secret.Decrypt("MP_SEND_API_AUTH")
	if err != nil {
		return err
	}

	img, err := image.Pull(ctx, "mailpit", "axllent/mailpit:latest")
	if err != nil {
		return err
	}

	_, err = docker.NewContainer(ctx, "mailpit", &docker.ContainerArgs{
		Image:   img.ImageId,
		Name:    pulumi.String("mailpit"),
		Restart: pulumi.String("unless-stopped"),
		Envs: pulumi.StringArray{
			pulumi.Sprintf("MP_SEND_API_AUTH=%s", credential),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(1025),
				External: pulumi.Int(1025),
			},
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(8025),
				External: pulumi.Int(8025),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: network.Name,
			},
		},
	})

	return err
}
