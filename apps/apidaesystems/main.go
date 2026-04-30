package main

import (
	"github.com/getsops/sops/v3/decrypt"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"gopkg.in/yaml.v3"
)

type serviceConfig struct {
	IsEnabled bool   `json:"enabled"`
	Image     string `json:"image"`
	Memory    int    `json:"memory"`
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		pulumiConfig := config.New(ctx, "")
		domain := pulumiConfig.Require("domain")

		var traefikSettings traefikConfig
		pulumiConfig.RequireObject("traefik", &traefikSettings)
		var homepageSettings serviceConfig
		pulumiConfig.RequireObject("homepage", &homepageSettings)
		var radicleSettings serviceConfig
		pulumiConfig.RequireObject("radicle", &radicleSettings)
		var cgitSettings serviceConfig
		pulumiConfig.RequireObject("cgit", &cgitSettings)
		var glancesSettings serviceConfig
		pulumiConfig.RequireObject("glances", &glancesSettings)
		var grafanaSettings serviceConfig
		pulumiConfig.RequireObject("grafana", &grafanaSettings)
		var natsSettings serviceConfig
		pulumiConfig.RequireObject("nats", &natsSettings)
		var homeAssistantSettings serviceConfig
		pulumiConfig.RequireObject("home-assistant", &homeAssistantSettings)
		var postgresqlSettings serviceConfig
		pulumiConfig.RequireObject("postgresql", &postgresqlSettings)
		var authentikSettings serviceConfig
		pulumiConfig.RequireObject("authentik", &authentikSettings)
		var penpotSettings serviceConfig
		pulumiConfig.RequireObject("penpot", &penpotSettings)
		var boreSettings serviceConfig
		pulumiConfig.RequireObject("bore", &boreSettings)

		cleartext, err := decrypt.File("../../secrets.yaml", "yaml")
		if err != nil {
			return err
		}
		var secrets map[string]string
		if err := yaml.Unmarshal(cleartext, &secrets); err != nil {
			return err
		}

		proxyNetwork, err := docker.NewNetwork(ctx, "proxy", &docker.NetworkArgs{
			Name: pulumi.String("proxy"),
			Labels: docker.NetworkLabelArray{
				&docker.NetworkLabelArgs{
					Label: pulumi.String("managed-by"),
					Value: pulumi.String("pulumi"),
				},
			},
		})
		if err != nil {
			return err
		}
		ctx.Export("network", proxyNetwork.Name)

		if err := createTraefik(ctx, proxyNetwork, traefikSettings); err != nil {
			return err
		}

		homepageEnvs := pulumi.StringArray{
			pulumi.String("HOMEPAGE_ALLOWED_HOSTS=" + domain + ",www." + domain),
			pulumi.String("HOMEPAGE_VAR_DOMAIN=" + domain),
		}

		applicationServices := ""
		if grafanaSettings.IsEnabled {
			applicationServices += grafanaServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_GRAFANA_PASSWORD="+secrets["GRAFANA_ADMIN_PASSWORD"]))
		}
		if homeAssistantSettings.IsEnabled {
			applicationServices += homeAssistantServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_HA_ACCESS_TOKEN="+secrets["HA_ACCESS_TOKEN"]))
		}
		if authentikSettings.IsEnabled {
			applicationServices += authentikServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_AUTHENTIK_API_TOKEN="+secrets["AUTHENTIK_API_TOKEN"]))
		}
		if radicleSettings.IsEnabled {
			applicationServices += radicleServiceYAML
		}
		if cgitSettings.IsEnabled {
			applicationServices += cgitServiceYAML
		}
		if natsSettings.IsEnabled {
			applicationServices += natsServiceYAML
		}
		if boreSettings.IsEnabled {
			applicationServices += boreServiceYAML
		}
		applicationServices += traefikServiceYAML

		servicesYAML := "- Services:\n" + applicationServices
		if glancesSettings.IsEnabled {
			servicesYAML += "\n- System:\n" + glancesServiceYAML
		}
		servicesYAML += "\n- Calendar:\n" + calendarServiceYAML
		if glancesSettings.IsEnabled {
			servicesYAML += "\n- Monitoring:\n" + glancesServiceYAML
		}
		servicesYAML += "\n- Schedule:\n" + calendarServiceYAML

		if err := createHomepage(ctx, proxyNetwork, servicesYAML, homepageEnvs, domain, homepageSettings); err != nil {
			return err
		}

		if radicleSettings.IsEnabled {
			if err := createRadicle(ctx, proxyNetwork, secrets, domain, radicleSettings); err != nil {
				return err
			}
		}

		if cgitSettings.IsEnabled {
			if err := createCgit(ctx, proxyNetwork, domain, cgitSettings); err != nil {
				return err
			}
		}

		if grafanaSettings.IsEnabled {
			if err := createGrafana(ctx, proxyNetwork, secrets, domain, grafanaSettings); err != nil {
				return err
			}
		}

		if glancesSettings.IsEnabled {
			if err := createGlances(ctx, proxyNetwork, glancesSettings); err != nil {
				return err
			}
		}

		var natsContainer *docker.Container
		if natsSettings.IsEnabled {
			natsContainer, err = createNATS(ctx, proxyNetwork, secrets, natsSettings)
			if err != nil {
				return err
			}
		}

		if homeAssistantSettings.IsEnabled {
			if err := createHomeAssistant(ctx, proxyNetwork, domain, homeAssistantSettings); err != nil {
				return err
			}
		}

		var postgresqlContainer *docker.Container
		if postgresqlSettings.IsEnabled || authentikSettings.IsEnabled || grafanaSettings.IsEnabled {
			schemaSQL, err := resolveSchemaSQL()
			if err != nil {
				return err
			}

			initScripts := docker.ContainerUploadArray{
				&docker.ContainerUploadArgs{
					File:    pulumi.String("/docker-entrypoint-initdb.d/01-schema.sql"),
					Content: pulumi.String(schemaSQL),
				},
			}
			if authentikSettings.IsEnabled {
				initScripts = append(docker.ContainerUploadArray{
					&docker.ContainerUploadArgs{
						File:    pulumi.String("/docker-entrypoint-initdb.d/00-authentik.sh"),
						Content: pulumi.String(authentikInitScript(secrets)),
					},
				}, initScripts...)
			}
			if grafanaSettings.IsEnabled {
				initScripts = append(docker.ContainerUploadArray{
					&docker.ContainerUploadArgs{
						File:    pulumi.String("/docker-entrypoint-initdb.d/00-grafana.sh"),
						Content: pulumi.String(grafanaInitScript()),
					},
				}, initScripts...)
			}

			var postgresqlDependencies []pulumi.Resource
			if natsContainer != nil {
				postgresqlDependencies = append(postgresqlDependencies, natsContainer)
			}
			postgresqlContainer, err = createPostgreSQL(ctx, proxyNetwork, secrets, postgresqlSettings, initScripts, postgresqlDependencies...)
			if err != nil {
				return err
			}
		}

		if authentikSettings.IsEnabled {
			authentikImage, authentikMedia, err := createAuthentikServer(ctx, proxyNetwork, secrets, domain, postgresqlContainer, authentikSettings)
			if err != nil {
				return err
			}
			if err := createAuthentikWorker(ctx, proxyNetwork, secrets, authentikImage, authentikMedia, postgresqlContainer, authentikSettings); err != nil {
				return err
			}
		}

		if penpotSettings.IsEnabled {
			if err := createPenpot(ctx, secrets, domain); err != nil {
				return err
			}
		}

		if boreSettings.IsEnabled {
			if err := createBore(ctx, proxyNetwork, secrets, boreSettings); err != nil {
				return err
			}
		}

		return nil
	})
}
