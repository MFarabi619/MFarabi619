package providers

import (
	"github.com/pulumi/pulumi-hcloud/sdk/go/hcloud"
	"github.com/pulumi/pulumi-std/sdk/go/std"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	//"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func Hetzner(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}

	// cfg := config.New(ctx, "")
	// hcloudToken := cfg.RequireObject("hcloud:token")

	invokeFile, err := std.File(ctx, &std.FileArgs{
		Input: "../../.ssh/id_ed25519.pub",
	}, nil)

	if err != nil {
		return err
	}

	sshKey, err := hcloud.NewSshKey(ctx, "ssh-key", &hcloud.SshKeyArgs{
		Name:      pulumi.String("mfarabi619@gmail.com"),
		PublicKey: pulumi.String(invokeFile.Result),
		Labels: pulumi.StringMap{
			"owner":  pulumi.String("mfarabi"),
			"pulumi": pulumi.String("true"),
		},
	})

	if err != nil {
		return err
	}

	server, err := hcloud.NewServer(ctx, "ubuntu-24.04", &hcloud.ServerArgs{
		Name:       pulumi.String("ubuntu-24.04"),
		Image:      pulumi.String("ubuntu-24.04"),
		ServerType: pulumi.String("cpx11"),
		Datacenter: pulumi.String("ash-dc1"),
		// Location:               pulumi.String("ash"),
		DeleteProtection:       pulumi.Bool(false),
		KeepDisk:               pulumi.Bool(false),
		RebuildProtection:      pulumi.Bool(false),
		Backups:                pulumi.Bool(false),
		ShutdownBeforeDeletion: pulumi.Bool(false),
		PublicNets: hcloud.ServerPublicNetArray{
			&hcloud.ServerPublicNetArgs{
				Ipv4Enabled: pulumi.Bool(true),
				Ipv6Enabled: pulumi.Bool(true),
			},
		},
		SshKeys: pulumi.StringArray{
			sshKey.Name,
		},
		Labels: pulumi.StringMap{
			"pulumi": pulumi.String("true"),
		},
	})
	if err != nil {
		return err
	}

	ctx.Export("ubuntu-24.04 IPV4", server.Ipv4Address)
	ctx.Export("ubuntu-24.04 IPV6", server.Ipv6Address)
	ctx.Export("ubuntu-24.04 PrimaryDiskSize", server.PrimaryDiskSize)
	ctx.Export("ubuntu-24.04 Status", server.Status)

	return nil
}
