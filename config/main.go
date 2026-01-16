// pulumi up -C config -fy -v=3
// pulumi state delete -C config

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

		err = providers.Tailscale(ctx, false)
		if err != nil {
			return err
		}

		err = providers.Vercel(ctx, true)
		if err != nil {
			return err
		}

		_, err = providers.DigitalOcean(ctx, false)

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

		err = providers.GitHub(ctx, false)
		if err != nil {
			return err
		}

		err = providers.OCI(ctx, true)
		if err != nil {
			return err
		}

		err = providers.Hetzner(ctx, false)
		if err != nil {
			return err
		}

		err = providers.Command(ctx, true)
		if err != nil {
			return err
		}

		err = providers.Docker(ctx, false)
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
