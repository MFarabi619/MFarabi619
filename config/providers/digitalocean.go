package providers

import (
	"github.com/pulumi/pulumi-digitalocean/sdk/v4/go/digitalocean"
	"github.com/pulumi/pulumi-std/sdk/go/std"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func SetupDigitalOcean(ctx *pulumi.Context) (*digitalocean.Droplet, error) {
	invokeFile, err := std.File(ctx, &std.FileArgs{
		Input: "../../.ssh/id_ed25519.pub",
	}, nil)

	if err != nil {
		return nil, err
	}

	sshKey, err := digitalocean.NewSshKey(ctx, "framework-desktop", &digitalocean.SshKeyArgs{
		Name:      pulumi.String("framework-desktop"),
		PublicKey: pulumi.String(invokeFile.Result),
	})

	if err != nil {
		return nil, err
	}

	vm, err := digitalocean.NewDroplet(ctx, "ubuntu-s-1vcpu-512mb-10gb-tor1-01", &digitalocean.DropletArgs{
		Name:    pulumi.String("ubuntu-s-1vcpu-512mb-10gb-tor1-01"),
		Image:   pulumi.String("ubuntu-24-04-x64"),
		Region:  pulumi.String(digitalocean.RegionTOR1),
		Size:    pulumi.String(digitalocean.DropletSlugDropletS1VCPU512MB10GB),
		Backups: pulumi.Bool(false),

		SshKeys: pulumi.StringArray{
			sshKey.Fingerprint,
		},

		Tags: pulumi.StringArray{
			pulumi.String("dev"),
		},
	})

	if err != nil {
		return nil, err
	}

	_, err = digitalocean.NewProject(ctx, "openws", &digitalocean.ProjectArgs{
		Name:        pulumi.String("openws"),
		Environment: pulumi.String("Development"),
		Purpose:     pulumi.String("Web Application"),
		Description: pulumi.String("A project to represent development resources."),

		Resources: pulumi.StringArray{
		vm.DropletUrn,
		},
	})

	if err != nil {
		return nil, err
	}

	return vm, nil
}
