package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	grafana "github.com/pulumiverse/pulumi-grafana/sdk/v2/go/grafana"
	appsv2 "github.com/pulumiverse/pulumi-grafana/sdk/v2/go/grafana/apps/v2"
	"github.com/pulumiverse/pulumi-grafana/sdk/v2/go/grafana/oss"
)

const grafanaServiceYAML = `    - Grafana:
        href: https://grafana.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://grafana.{{HOMEPAGE_VAR_DOMAIN}}
        icon: grafana.svg
        server: local
        container: grafana
        widget:
          type: grafana
          version: 2
          url: http://grafana:3000
          username: admin
          password: "{{HOMEPAGE_VAR_GRAFANA_PASSWORD}}"
`

func createGrafana(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, domain string, settings serviceConfig) error {
	data, err := createVolume(ctx, "grafana-data")
	if err != nil {
		return err
	}

	image, err := pullImage(ctx, "grafana", settings.Image)
	if err != nil {
		return err
	}

	container, err := docker.NewContainer(ctx, "grafana", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("grafana"),
		Hostname:            pulumi.String("grafana"),
		User:                pulumi.String("472"),
		Init:                pulumi.Bool(true),
		Restart:             pulumi.String("unless-stopped"),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(120),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(512),
		DestroyGraceSeconds: pulumi.Int(10),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
		},
		SecurityOpts: pulumi.StringArray{
			pulumi.String("no-new-privileges:true"),
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Tmpfs: pulumi.StringMap{
			"/tmp": pulumi.String("size=64m"),
		},
		Labels: createTraefikLabels("grafana", "grafana."+domain, "3000"),
		Envs: pulumi.StringArray{
			pulumi.String("GF_DEFAULT_INSTANCE_NAME=Apidae Systems"),
			pulumi.String("GF_SERVER_DOMAIN=grafana." + domain),
			pulumi.String("GF_SERVER_ROOT_URL=https://grafana." + domain + "/"),
			pulumi.String("GF_SERVER_ENABLE_GZIP=true"),
			pulumi.String("GF_FEATURE_TOGGLES_ENABLE=provisioning,grafanaconThemes"),
			pulumi.String("GF_PUBLIC_DASHBOARDS_ENABLED=true"),

			pulumi.String("GF_SECURITY_ADMIN_USER=admin"),
			pulumi.String("GF_SECURITY_ADMIN_PASSWORD=" + secrets["GRAFANA_ADMIN_PASSWORD"]),
			pulumi.String("GF_SECURITY_ALLOW_EMBEDDING=true"),
			pulumi.String("GF_SECURITY_COOKIE_SECURE=true"),
			pulumi.String("GF_SECURITY_COOKIE_SAMESITE=none"),

			pulumi.String("GF_AUTH_DISABLE_LOGIN_FORM=false"),
			pulumi.String("GF_AUTH_AUTO_ASSIGN_ORG_NAME=Apidae Systems"),
			pulumi.String("GF_USERS_ALLOW_SIGN_UP=false"),

			pulumi.String("GF_AUTH_GOOGLE_ENABLED=true"),
			pulumi.String("GF_AUTH_GOOGLE_CLIENT_ID=" + secrets["GF_AUTH_GOOGLE_CLIENT_ID"]),
			pulumi.String("GF_AUTH_GOOGLE_CLIENT_SECRET=" + secrets["GF_AUTH_GOOGLE_CLIENT_SECRET"]),
			pulumi.String("GF_AUTH_GOOGLE_SCOPES=openid email profile"),
			pulumi.String("GF_AUTH_GOOGLE_AUTH_URL=https://accounts.google.com/o/oauth2/v2/auth"),
			pulumi.String("GF_AUTH_GOOGLE_TOKEN_URL=https://oauth2.googleapis.com/token"),
			pulumi.String("GF_AUTH_GOOGLE_ALLOWED_DOMAINS=apidaesystems.ca"),
			pulumi.String("GF_AUTH_GOOGLE_ALLOW_SIGN_UP=true"),

			pulumi.String("GF_SMTP_ENABLED=true"),
			pulumi.String("GF_SMTP_HOST=smtp.gmail.com:587"),
			pulumi.String("GF_SMTP_USER=" + secrets["GRAFANA_SMTP_USER"]),
			pulumi.String("GF_SMTP_PASSWORD=" + secrets["GRAFANA_SMTP_PASSWORD"]),
			pulumi.String("GF_SMTP_FROM_ADDRESS=admin@grafana." + domain),

			pulumi.String("GF_ANALYTICS_CHECK_FOR_UPDATES=false"),
			pulumi.String("GF_ANALYTICS_REPORTING_ENABLED=false"),
			pulumi.String("GF_ANALYTICS_FEEDBACK_LINKS_ENABLED=false"),

			pulumi.String("GF_DATE_FORMATS_DEFAULT_WEEK_START=monday"),
			pulumi.String("GF_DATE_FORMATS_DEFAULT_TIMEZONE=America/Toronto"),

			pulumi.String("GF_LOG_MODE=console"),
			pulumi.String("GF_LOG_FORMAT=json"),

			pulumi.String("GF_PLUGINS_PREINSTALL=yesoreyeram-infinity-datasource,operato-windrose-panel,grafana-pathfinder-app,orchestracities-iconstat-panel"),
			pulumi.String("GF_PLUGINS_PLUGIN_CATALOG_HIDDEN_PLUGINS=" +
				"prometheus,loki,tempo,jaeger,zipkin,elasticsearch,influxdb,graphite,opentsdb,mysql,mssql,alertmanager,cloudwatch,grafana-azure-monitor-datasource,grafana-pyroscope-datasource,parca,testdata," +
				"grafana-cube-datasource,ekacnet-cubismgrafana-panel,grafana-databricks-datasource,grafana-datadog-datasource,crestdata-dellemcpowerscale-datasource," +
				"grafana-timestream-datasource,anodot-datasource,grafana-atlassianstatuspage-datasource,grafana-x-ray-datasource,aws-datasource-provisioner-app," +
				"grafana-iot-sitewise-datasource,grafana-iot-twinmaker-app,axiomhq-axiom-datasource,azure-monitor-app,grafana-azurecosmosdb-datasource," +
				"victoriametrics-logs-datasource,grafana-wavefront-datasource,svennergr-hackerone-datasource,apricote-hcloud-datasource," +
				"groonga-datasource,needleinajaystack-haystack-datasource,grafana-dynatrace-datasource,embrace-app," +
				"crestdata-fortigate-datasource,fraunhoferiosb-frost-datasource,stackdriver,googlecloud-trace-datasource," +
				"factry-untimely-datasource,akdor1154-vega-panel,grafana-vercel-datasource,vertica-grafana-datasource," +
				"grafana-strava-datasource,streamr-datasource,fiskaly-surrealdb-datasource,grafana-surrealdb-datasource," +
				"grafana-splunk-datasource,grafana-splunk-monitoring-datasource,grafana-snowflake-datasource," +
				"runreveal-datasource,grafana-salesforce-datasource,questdb-questdb-datasource,quickwit-quickwit-datasource," +
				"grafana-pagerduty-datasource,grafana-oracle-datasource,phenisyslab-msteamsobservability-app,moogsoft-aiops-app," +
				"hydrolix-hydrolix-datasource,grafana-db2-datasource,rocketsoftware-omegamon-app"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/var/lib/grafana"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD"),
				pulumi.String("wget"),
				pulumi.String("--no-verbose"),
				pulumi.String("--tries=1"),
				pulumi.String("--spider"),
				pulumi.String("http://localhost:3000/api/health"),
			},
			Interval:    pulumi.String("10s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("30s"),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(3000),
				External: pulumi.Int(3000),
				Ip:       pulumi.String("127.0.0.1"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, pulumi.AdditionalSecretOutputs([]string{"envs"}))
	if err != nil {
		return err
	}

	grafanaProvider, err := grafana.NewProvider(ctx, "grafana", &grafana.ProviderArgs{
		Url:  pulumi.String("http://localhost:3000"),
		Auth: pulumi.Sprintf("admin:%s", secrets["GRAFANA_ADMIN_PASSWORD"]),
	}, pulumi.DependsOn([]pulumi.Resource{container}))
	if err != nil {
		return err
	}

	_, err = oss.NewDataSource(ctx, "grafana-postgresql", &oss.DataSourceArgs{
		Type:            pulumi.String("postgres"),
		Name:            pulumi.String("PostgreSQL"),
		Url:             pulumi.String("postgresql:5432"),
		Username:        pulumi.String("grafana"),
		DatabaseName:    pulumi.String("grafana"),
		JsonDataEncoded: pulumi.String(`{"sslmode":"disable","postgresVersion":1500,"timescaledb":true}`),
		IsDefault:       pulumi.Bool(true),
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	_, err = oss.NewDataSource(ctx, "grafana-infinity", &oss.DataSourceArgs{
		Type: pulumi.String("yesoreyeram-infinity-datasource"),
		Name: pulumi.String("Infinity"),
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	folder, err := oss.NewFolder(ctx, "grafana-apidae-folder", &oss.FolderArgs{
		Title:                    pulumi.String("Apidae Systems"),
		PreventDestroyIfNotEmpty: pulumi.Bool(true),
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	dashboardSpecJSON, err := buildHomeDashboardSpec()
	if err != nil {
		return err
	}

	dashboard, err := appsv2.NewDashboard(ctx, "grafana-home-dashboard", &appsv2.DashboardArgs{
		Metadata: &appsv2.DashboardMetadataArgs{
			Uid:       pulumi.String("apidae-home"),
			FolderUid: folder.Uid,
		},
		Spec: &appsv2.DashboardSpecArgs{
			Json: pulumi.String(dashboardSpecJSON),
		},
		Options: &appsv2.DashboardOptionsArgs{
			Overwrite: pulumi.Bool(true),
		},
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	_, err = oss.NewDashboardPublic(ctx, "grafana-home-public", &oss.DashboardPublicArgs{
		DashboardUid:         pulumi.String("apidae-home"),
		IsEnabled:            pulumi.Bool(true),
		Share:                pulumi.String("public"),
		TimeSelectionEnabled: pulumi.Bool(true),
		AnnotationsEnabled:   pulumi.Bool(true),
	}, pulumi.Provider(grafanaProvider), pulumi.DependsOn([]pulumi.Resource{dashboard}))
	if err != nil {
		return err
	}

	_, err = oss.NewOrganizationPreferences(ctx, "grafana-org-preferences", &oss.OrganizationPreferencesArgs{
		Theme:            pulumi.String("gildedgrove"),
		Timezone:         pulumi.String("America/Toronto"),
		WeekStart:        pulumi.String("monday"),
		HomeDashboardUid: pulumi.String("apidae-home"),
	}, pulumi.Provider(grafanaProvider), pulumi.DependsOn([]pulumi.Resource{dashboard}))
	if err != nil {
		return err
	}

	serviceAccount, err := oss.NewServiceAccount(ctx, "grafana-homepage", &oss.ServiceAccountArgs{
		Name: pulumi.String("homepage"),
		Role: pulumi.String("Viewer"),
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	token, err := oss.NewServiceAccountToken(ctx, "grafana-homepage-token", &oss.ServiceAccountTokenArgs{
		ServiceAccountId: serviceAccount.ID(),
		Name:             pulumi.String("homepage"),
	}, pulumi.Provider(grafanaProvider))
	if err != nil {
		return err
	}

	ctx.Export("grafana image", image.RepoDigest)
	ctx.Export("grafana id", container.ID())
	ctx.Export("grafana data", data.Mountpoint)
	ctx.Export("grafana service account token", token.Key)

	return nil
}
