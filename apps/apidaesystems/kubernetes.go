package main

import (
	"github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/helm/v3"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func createPenpot(ctx *pulumi.Context, secrets map[string]string, domain string) error {
	release, err := helm.NewRelease(ctx, "penpot", &helm.ReleaseArgs{
		Chart:           pulumi.String("penpot"),
		Version:         pulumi.String("0.40.0"),
		Namespace:       pulumi.String("penpot"),
		CreateNamespace: pulumi.Bool(true),
		RepositoryOpts: &helm.RepositoryOptsArgs{
			Repo: pulumi.String("http://helm.penpot.app"),
		},
		Values: pulumi.Map{
			"global": pulumi.Map{
				"postgresqlEnabled": pulumi.Bool(true),
				"redisEnabled":      pulumi.Bool(true),
			},
			"config": pulumi.Map{
				"publicUri":    pulumi.String("https://penpot." + domain),
				"apiSecretKey": pulumi.String(secrets["PENPOT_SECRET_KEY"]),
			},
			"frontend": pulumi.Map{
				"replicaCount": pulumi.Int(1),
			},
			"backend": pulumi.Map{
				"replicaCount": pulumi.Int(1),
			},
			"exporter": pulumi.Map{
				"replicaCount": pulumi.Int(1),
			},
			"ingress": pulumi.Map{
				"enabled": pulumi.Bool(true),
				"path":    pulumi.String("/"),
				"hosts": pulumi.Array{
					pulumi.String("penpot." + domain),
				},
			},
			"persistence": pulumi.Map{
				"assets": pulumi.Map{
					"enabled": pulumi.Bool(true),
					"size":    pulumi.String("10Gi"),
				},
			},
		},
	})
	if err != nil {
		return err
	}

	ctx.Export("penpot version", release.Status.Version())

	return nil
}
