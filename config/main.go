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

		err = providers.SetupTailscale(ctx, true)

		if err != nil {
			return err
		}

		err = providers.SetupVercel(ctx, true)

		if err != nil {
			return err
		}

		_, err = providers.SetupDigitalOcean(ctx, false)

		if err != nil {
			return err
		}

		// website, err := providers.NewAwsS3Website(ctx, "my-website", providers.AwsS3WebsiteArgs{
		//	Files: []string{"index.html"},
		// })

		// if err != nil {
		//	return err
		// }

		// ctx.Export("url", website.Url)

		// FIXME: * POST https://api.github.com/user/gpg_keys: 404 Not Found []
		//		err = providers.SetupGitHub(ctx)
		//	if err != nil {
		//	return err
		//	}

		err = providers.SetupOracleCloud(ctx, true)
		if err != nil {
			return err
		}

		err = providers.MaintainFleet(ctx, true)
		if err != nil {
			return err
		}

		err = providers.ProvisionDockerContainers(ctx, false)
		if err != nil {
			return err
		}

		//	err = providers.ProvisionVirtualMachine(ctx, false)
		//	if err != nil {
		//		return err
		//		}

		return nil
	})
}
