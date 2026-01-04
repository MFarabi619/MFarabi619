// https://www.pulumi.com/registry/packages/command/
package providers

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-command/sdk/go/command/remote"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func MaintainFleet(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}

	// Optional: shared entropy / trigger
	random, err := local.NewCommand(ctx, "fleet-trigger", &local.CommandArgs{
		Create: pulumi.String("openssl rand -hex 16"),
	})

	if err != nil {
		return err
	}

	ctx.Export("openssl", random.Stdout)

	cmd, err := remote.NewCommand(ctx, "install nix on ubuntu", &remote.CommandArgs{
		Connection: &remote.ConnectionArgs{
			Host: pulumi.String("ubuntu"),
			User: pulumi.String("root"),
		},
		Create: pulumi.String("curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm --extra-conf 'trusted-users = root mfarabi'"),
		Delete: pulumi.String("/nix/nix-installer uninstall --no-confirm"),
		Update: pulumi.String(`
				apt update
				apt upgrade -y
      apt autoremove -y
			`),

		Logging: remote.LoggingStdout,
	})

	if err != nil {
		return err
	}

	ctx.Export("stdout", cmd.Stdout)

	cmd, err = remote.NewCommand(ctx, "clone repository on ubuntu", &remote.CommandArgs{
		Connection: &remote.ConnectionArgs{
			Host: pulumi.String("ubuntu"),
			User: pulumi.String("mfarabi"),
		},
		Create:  pulumi.String("git clone https://github.com/MFarabi619/MFarabi619"),
		Delete:  pulumi.String("rm -rf ~/MFarabi619"),
		Update:  pulumi.String("echo 'repo already cloned'"),
		Logging: remote.LoggingStdout,
	})

	if err != nil {
		return err
	}

	ctx.Export("stdout", cmd.Stdout)

	cmd, err = remote.NewCommand(ctx, "install nix ubuntu-s-1vcpu-1gb-50gb-mon1-01", &remote.CommandArgs{
		Connection: &remote.ConnectionArgs{
			Host: pulumi.String("ubuntu-s-1vcpu-1gb-50gb-mon1-01"),
			User: pulumi.String("root"),
		},
		Create: pulumi.String("curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm --extra-conf 'trusted-users = root ubuntu'"),
		Delete: pulumi.String("/nix/nix-installer uninstall --no-confirm"),
		Update: pulumi.String(`
				apt update
				apt upgrade -y
      apt autoremove -y
			`),

		Logging: remote.LoggingStdout,
	})

	if err != nil {
		return err
	}

	ctx.Export("stdout", cmd.Stdout)

	cmd, err = remote.NewCommand(ctx, "clone repository on ubuntu-s-1vcpu-1gb-50gb-mon1-01", &remote.CommandArgs{
		Connection: &remote.ConnectionArgs{
			Host: pulumi.String("ubuntu-s-1vcpu-1gb-50gb-mon1-01"),
			User: pulumi.String("ubuntu"),
		},
		Create:  pulumi.String("git clone https://github.com/MFarabi619/MFarabi619"),
		Delete:  pulumi.String("rm -rf ~/MFarabi619"),
		Update:  pulumi.String("echo 'repo already cloned'"),
		Logging: remote.LoggingStdout,
	})

	if err != nil {
		return err
	}

	ctx.Export("stdout", cmd.Stdout)

	return nil
}
