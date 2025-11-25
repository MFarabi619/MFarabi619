package providers

import (
	"github.com/pulumi/pulumi-tailscale/sdk/go/tailscale"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func SetupTailscale(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}

	_, err := tailscale.NewContacts(ctx, "contacts", &tailscale.ContactsArgs{
		Account: &tailscale.ContactsAccountArgs{
			Email: pulumi.String("mfarabi619@gmail.com"),
		},
		Security: &tailscale.ContactsSecurityArgs{
			Email: pulumi.String("mfarabi619@gmail.com"),
		},
		Support: &tailscale.ContactsSupportArgs{
			Email: pulumi.String("mfarabi619@gmail.com"),
		},
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	_, err = tailscale.NewTailnetSettings(ctx, "tailnet_settings", &tailscale.TailnetSettingsArgs{
		DevicesKeyDurationDays:                pulumi.Int(180),
		HttpsEnabled:                          pulumi.Bool(true),
		UsersApprovalOn:                       pulumi.Bool(true),
		DevicesAutoUpdatesOn:                  pulumi.Bool(false),
		UsersRoleAllowedToJoinExternalTailnet: pulumi.String("admin"),
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	return err
}
