package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"openws/providers"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		err := providers.SetupCloudflare(ctx)

		if err != nil {
			return err
		}

		// FIXME: * POST https://api.github.com/user/gpg_keys: 404 Not Found []
		//		err = providers.SetupGitHub(ctx)
		//	if err != nil {
		//	return err
		//	}

		err = providers.SetupVercel(ctx, true)

		if err != nil {
			return err
		}

		_, err = providers.SetupDigitalOcean(ctx, false)

		if err != nil {
			return err
		}

		return nil
	})
}
