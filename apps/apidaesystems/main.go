package main

import (
	"github.com/getsops/sops/v3/decrypt"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

const domain = "apidae.systems"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		enableCgit := true
		enableGrafana := true
		enableHomeAssistant := true
		enableMosquitto := false
		enablePostgreSQL := false
		enableAuthentik := false

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

		traefik, traefikImage, err := createTraefik(ctx, proxyNetwork)
		if err != nil {
			return err
		}
		ctx.Export("network", proxyNetwork.Name)
		ctx.Export("traefik image", traefikImage.RepoDigest)
		ctx.Export("traefik id", traefik.ID())

		servicesYAML := homepageServiceYAML
		homepageEnvs := pulumi.StringArray{
			pulumi.String("HOMEPAGE_ALLOWED_HOSTS=" + domain + ",www." + domain),
			pulumi.String("HOMEPAGE_VAR_DOMAIN=" + domain),
		}

		monitoringServices := ""
		if enableGrafana {
			monitoringServices += grafanaServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_GRAFANA_PASSWORD="+secrets["GRAFANA_ADMIN_PASSWORD"]))
		}
		if enableHomeAssistant {
			monitoringServices += homeAssistantServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_HA_ACCESS_TOKEN="+secrets["HA_ACCESS_TOKEN"]))
		}
		if monitoringServices != "" {
			servicesYAML += "\n- Monitoring:\n" + monitoringServices
		}

		if enableAuthentik {
			servicesYAML += "\n" + authentikServiceYAML
			homepageEnvs = append(homepageEnvs, pulumi.String("HOMEPAGE_VAR_AUTHENTIK_API_TOKEN="+secrets["AUTHENTIK_API_TOKEN"]))
		}

		homepage, homepageImage, err := createHomepage(ctx, proxyNetwork, servicesYAML, homepageEnvs)
		if err != nil {
			return err
		}
		ctx.Export("homepage image", homepageImage.RepoDigest)
		ctx.Export("homepage id", homepage.ID())

		if enableCgit {
			cgit, cgitImage, gitRepos, err := createCgit(ctx, proxyNetwork)
			if err != nil {
				return err
			}
			ctx.Export("cgit image", cgitImage.RepoDigest)
			ctx.Export("cgit id", cgit.ID())
			ctx.Export("git repos", gitRepos.Mountpoint)
		}

		if enableGrafana {
			grafana, grafanaImage, grafanaData, err := createGrafana(ctx, proxyNetwork, secrets)
			if err != nil {
				return err
			}
			ctx.Export("grafana image", grafanaImage.RepoDigest)
			ctx.Export("grafana id", grafana.ID())
			ctx.Export("grafana data", grafanaData.Mountpoint)
		}

		if enableMosquitto {
			mosquitto, mosquittoImage, err := createMosquitto(ctx, proxyNetwork)
			if err != nil {
				return err
			}
			ctx.Export("mosquitto image", mosquittoImage.RepoDigest)
			ctx.Export("mosquitto id", mosquitto.ID())
		}

		if enableHomeAssistant {
			homeassistant, homeassistantImage, homeassistantConfig, err := createHomeAssistant(ctx, proxyNetwork)
			if err != nil {
				return err
			}
			ctx.Export("homeassistant image", homeassistantImage.RepoDigest)
			ctx.Export("homeassistant id", homeassistant.ID())
			ctx.Export("homeassistant config", homeassistantConfig.Mountpoint)
		}

		if enablePostgreSQL {
			postgresql, postgresqlImage, postgresqlData, err := createPostgreSQL(ctx, proxyNetwork, secrets)
			if err != nil {
				return err
			}
			ctx.Export("postgresql image", postgresqlImage.RepoDigest)
			ctx.Export("postgresql id", postgresql.ID())
			ctx.Export("postgresql data", postgresqlData.Mountpoint)
		}

		if enableAuthentik {
			authentikServer, authentikImage, authentikMedia, err := createAuthentikServer(ctx, proxyNetwork, secrets)
			if err != nil {
				return err
			}

			authentikWorker, err := createAuthentikWorker(ctx, proxyNetwork, secrets, authentikImage, authentikMedia)
			if err != nil {
				return err
			}

			ctx.Export("authentik image", authentikImage.RepoDigest)
			ctx.Export("authentik server id", authentikServer.ID())
			ctx.Export("authentik worker id", authentikWorker.ID())
			ctx.Export("authentik media", authentikMedia.Mountpoint)
		}

		return nil
	})
}
