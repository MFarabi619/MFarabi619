package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"openws/providers"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		_, err := providers.SetupDigitalOcean(ctx)
		if err != nil {
			return err
		}

		err = providers.SetupCloudflare(ctx)
		if err != nil {
			return err
		}

		// FIXME: * POST https://api.github.com/user/gpg_keys: 404 Not Found []
		//		err = providers.SetupGitHub(ctx)
		//	if err != nil {
		//	return err
		//	}

		return nil
	})
}
