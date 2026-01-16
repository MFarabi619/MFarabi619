package providers

import (
	"github.com/pulumi/pulumi-terraform-provider/sdks/go/netlify/netlify"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func Netlify(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}
	_, err := netlify.NewDnsZone(ctx, "mfarabi", &netlify.DnsZoneArgs{
		Name:     pulumi.String("mfarabi.sh"),
		TeamSlug: pulumi.String("mfarabi619"),
	})
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteBuildSettings(ctx, "mfarabi", &netlify.SiteBuildSettingsArgs{
		BaseDirectory:    pulumi.String("apps/web"),
		BuildCommand:     pulumi.String(""),
		BuildImage:       pulumi.String("noble"),
		DeployPreviews:   pulumi.Bool(true),
		FunctionsRegion:  pulumi.String("us-east-2"),
		PrettyUrls:       pulumi.Bool(true),
		ProductionBranch: pulumi.String("main"),
		PublishDirectory: pulumi.String("dist"),
		SiteId:           pulumi.String("73e0c385-27e1-4710-813c-e05c49034b25"),
		StopBuilds:       pulumi.Bool(true),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteDomainSettings(ctx, "mfarabi", &netlify.SiteDomainSettingsArgs{
		CustomDomain: pulumi.String("mfarabi.sh"),
		DomainAliases: pulumi.StringArray{
			pulumi.String("2025.mfarabi.dev"),
		},
		SiteId: pulumi.String("73e0c385-27e1-4710-813c-e05c49034b25"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteBuildSettings(ctx, "fumadocs-payloadcms", &netlify.SiteBuildSettingsArgs{
		BuildCommand:     pulumi.String("pnpm build"),
		BuildImage:       pulumi.String("noble"),
		DeployPreviews:   pulumi.Bool(true),
		FunctionsRegion:  pulumi.String("us-east-2"),
		PrettyUrls:       pulumi.Bool(true),
		ProductionBranch: pulumi.String("main"),
		PublishDirectory: pulumi.String(".next"),
		SiteId:           pulumi.String("a555ed7b-5253-49c1-8ac2-157022031411"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}
	_, err = netlify.NewSiteDomainSettings(ctx, "fumadocs-payloadcms", &netlify.SiteDomainSettingsArgs{
		SiteId: pulumi.String("a555ed7b-5253-49c1-8ac2-157022031411"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteBuildSettings(ctx, "cunext", &netlify.SiteBuildSettingsArgs{
		BaseDirectory:    pulumi.String("slides"),
		BuildCommand:     pulumi.String("npm run build"),
		BuildImage:       pulumi.String("noble"),
		DeployPreviews:   pulumi.Bool(true),
		FunctionsRegion:  pulumi.String("us-east-1"),
		PrettyUrls:       pulumi.Bool(true),
		ProductionBranch: pulumi.String("main"),
		PublishDirectory: pulumi.String("dist"),
		SiteId:           pulumi.String("44e6a006-b7b8-447e-b348-d85af14f7610"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteDomainSettings(ctx, "cunext", &netlify.SiteDomainSettingsArgs{
		SiteId: pulumi.String("44e6a006-b7b8-447e-b348-d85af14f7610"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteBuildSettings(ctx, "microvisor", &netlify.SiteBuildSettingsArgs{
		BuildCommand:     pulumi.String("pnpx likec4 build"),
		BuildImage:       pulumi.String("noble"),
		DeployPreviews:   pulumi.Bool(true),
		FunctionsRegion:  pulumi.String("us-east-2"),
		PrettyUrls:       pulumi.Bool(true),
		ProductionBranch: pulumi.String("main"),
		PublishDirectory: pulumi.String("dist"),
		SiteId:           pulumi.String("b6f1878f-1790-4165-b9e2-600063466bb7"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = netlify.NewSiteDomainSettings(ctx, "microvisor", &netlify.SiteDomainSettingsArgs{CustomDomain: pulumi.String("microvisor.dev"),
		SiteId: pulumi.String("b6f1878f-1790-4165-b9e2-600063466bb7"),
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	return nil
}
