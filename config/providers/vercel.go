package providers

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-vercel/sdk/v3/go/vercel"
)

func Vercel(ctx *pulumi.Context, enableVercel bool) error {
	if !enableVercel {
		return nil
	}

	_, err := vercel.NewProject(ctx, "fumadocs-payloadcms", &vercel.ProjectArgs{
		AutoAssignCustomDomains:                       pulumi.Bool(true),
		AutomaticallyExposeSystemEnvironmentVariables: pulumi.Bool(true),
		BuildCommand:      pulumi.String("pnpm build"),
		Framework:         pulumi.String("nextjs"),
		GitForkProtection: pulumi.Bool(true),
		GitRepository: &vercel.ProjectGitRepositoryArgs{
			ProductionBranch: pulumi.String("main"),
			Repo:             pulumi.String("MFarabi619/fumadocs-payloadcms"),
			Type:             pulumi.String("github"),
		},
		InstallCommand: pulumi.String("pnpm i"),
		Name:           pulumi.String("fumadocs-payloadcms"),
		NodeVersion:    pulumi.String("22.x"),
		OidcTokenConfig: &vercel.ProjectOidcTokenConfigArgs{
			Enabled:    pulumi.Bool(true),
			IssuerMode: pulumi.String("team"),
		},
		PrioritiseProductionBuilds: pulumi.Bool(true),
		VercelAuthentication: &vercel.ProjectVercelAuthenticationArgs{
			DeploymentType: pulumi.String("standard_protection_new"),
		},
	}, pulumi.Protect(true))
	if err != nil {
		return err
	}

	_, err = vercel.NewProject(ctx, "lunar-quake", &vercel.ProjectArgs{
		AutoAssignCustomDomains:                       pulumi.Bool(true),
		AutomaticallyExposeSystemEnvironmentVariables: pulumi.Bool(true),
		Framework:         pulumi.String("nextjs"),
		GitForkProtection: pulumi.Bool(true),
		GitRepository: &vercel.ProjectGitRepositoryArgs{
			ProductionBranch: pulumi.String("main"),
			Repo:             pulumi.String("MFarabi619/LunarQuake"),
			Type:             pulumi.String("github"),
		},
		Name:        pulumi.String("lunar-quake"),
		NodeVersion: pulumi.String("18.x"),
		OidcTokenConfig: &vercel.ProjectOidcTokenConfigArgs{
			Enabled:    pulumi.Bool(true),
			IssuerMode: pulumi.String("team"),
		},
		ResourceConfig: &vercel.ProjectResourceConfigArgs{
			FunctionDefaultCpuType: pulumi.String("standard_legacy"),
			FunctionDefaultRegions: pulumi.StringArray{
				pulumi.String("iad1"),
			},
		},
		RootDirectory: pulumi.String("frontend"),
		VercelAuthentication: &vercel.ProjectVercelAuthenticationArgs{
			DeploymentType: pulumi.String("none"),
		},
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}
	_, err = vercel.NewProject(ctx, "personal-portfolio-website", &vercel.ProjectArgs{
		AutomaticallyExposeSystemEnvironmentVariables: pulumi.Bool(true),
		Framework:         pulumi.String("vite"),
		GitForkProtection: pulumi.Bool(true),
		GitRepository: &vercel.ProjectGitRepositoryArgs{
			ProductionBranch: pulumi.String("main"),
			Repo:             pulumi.String("MFarabi619/personal-portfolio-website"),
			Type:             pulumi.String("github"),
		},
		Name:        pulumi.String("personal-portfolio-website"),
		NodeVersion: pulumi.String("18.x"),
		OidcTokenConfig: &vercel.ProjectOidcTokenConfigArgs{
			Enabled:    pulumi.Bool(true),
			IssuerMode: pulumi.String("team"),
		},
		VercelAuthentication: &vercel.ProjectVercelAuthenticationArgs{
			DeploymentType: pulumi.String("none"),
		},
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	_, err = vercel.NewProjectDomain(ctx, "personal-portfolio-website", &vercel.ProjectDomainArgs{
		Domain:    pulumi.String("mfarabi.dev"),
		ProjectId: pulumi.String("prj_LCGEM3EiR0KuH3KOtOSz6zm8JL9D"),
	}, pulumi.Protect(false))
	if err != nil {
		return err
	}

	_, err = vercel.NewProjectDomain(ctx, "2023.mfarabi.dev", &vercel.ProjectDomainArgs{
		Domain:    pulumi.String("2023.mfarabi.dev"),
		ProjectId: pulumi.String("prj_LCGEM3EiR0KuH3KOtOSz6zm8JL9D"),
	}, pulumi.Protect(false))
	if err != nil {
		return err
	}

	_, err = vercel.NewProjectDomain(ctx, "www.mfarabi.dev", &vercel.ProjectDomainArgs{
		Domain:    pulumi.String("www.mfarabi.dev"),
		ProjectId: pulumi.String("prj_LCGEM3EiR0KuH3KOtOSz6zm8JL9D"),
	}, pulumi.Protect(false))
	if err != nil {
		return err
	}

	_, err = vercel.NewProject(ctx, "github-readme-stats", &vercel.ProjectArgs{
		AutomaticallyExposeSystemEnvironmentVariables: pulumi.Bool(true),
		GitForkProtection: pulumi.Bool(true),
		GitRepository: &vercel.ProjectGitRepositoryArgs{
			ProductionBranch: pulumi.String("master"),
			Repo:             pulumi.String("MFarabi619/github-readme-stats"),
			Type:             pulumi.String("github"),
		},
		Name:        pulumi.String("github-readme-stats"),
		NodeVersion: pulumi.String("22.x"),
		OidcTokenConfig: &vercel.ProjectOidcTokenConfigArgs{
			Enabled:    pulumi.Bool(true),
			IssuerMode: pulumi.String("team"),
		},
		VercelAuthentication: &vercel.ProjectVercelAuthenticationArgs{
			DeploymentType: pulumi.String("none"),
		},
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	_, err = vercel.NewProject(ctx, "github-readme-streak-stats-vercel", &vercel.ProjectArgs{
		AutoAssignCustomDomains:                       pulumi.Bool(true),
		AutomaticallyExposeSystemEnvironmentVariables: pulumi.Bool(true),
		GitForkProtection:                             pulumi.Bool(true),
		GitRepository: &vercel.ProjectGitRepositoryArgs{
			ProductionBranch: pulumi.String("main"),
			Repo:             pulumi.String("MFarabi619/github-readme-streak-stats-vercel"),
			Type:             pulumi.String("github"),
		},
		Name:        pulumi.String("github-readme-streak-stats-vercel"),
		NodeVersion: pulumi.String("18.x"),
		OidcTokenConfig: &vercel.ProjectOidcTokenConfigArgs{
			Enabled:    pulumi.Bool(true),
			IssuerMode: pulumi.String("team"),
		},
		VercelAuthentication: &vercel.ProjectVercelAuthenticationArgs{
			DeploymentType: pulumi.String("none"),
		},
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	return err
}
