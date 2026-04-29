package main

import (
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
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

func createGrafana(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string) (*docker.Container, *docker.RemoteImage, *docker.Volume, error) {
	data, err := docker.NewVolume(ctx, "grafana-data", &docker.VolumeArgs{
		Name: pulumi.String("grafana-data"),
		Labels: docker.VolumeLabelArray{
			&docker.VolumeLabelArgs{
				Label: pulumi.String("managed-by"),
				Value: pulumi.String("pulumi"),
			},
		},
	})
	if err != nil {
		return nil, nil, nil, err
	}

	image, err := docker.NewRemoteImage(ctx, "grafana", &docker.RemoteImageArgs{
		Name:        pulumi.String("grafana/grafana:latest"),
		KeepLocally: pulumi.Bool(true),
	})
	if err != nil {
		return nil, nil, nil, err
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
		Memory:              pulumi.Int(512),
		MemorySwap:          pulumi.Int(512),
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
			pulumi.String("GF_SERVER_ROOT_URL=https://grafana." + domain + "/"),
			pulumi.String("GF_SERVER_ENABLE_GZIP=true"),
			pulumi.String("GF_USERS_ALLOW_SIGN_UP=false"),
			pulumi.String("GF_ANALYTICS_CHECK_FOR_UPDATES=false"),
			pulumi.String("GF_ANALYTICS_REPORTING_ENABLED=false"),
			pulumi.String("GF_ANALYTICS_FEEDBACK_LINKS_ENABLED=false"),
			pulumi.String("GF_DATE_FORMATS_DEFAULT_WEEK_START=monday"),
			pulumi.String("GF_DATE_FORMATS_DEFAULT_TIMEZONE=America/Toronto"),
			pulumi.String("GF_PLUGINS_PREINSTALL=yesoreyeram-infinity-datasource,operato-windrose-panel,grafana-pathfinder-app,orchestracities-iconstat-panel"),
			pulumi.String("GF_LOG_MODE=console"),
			pulumi.String("GF_LOG_FORMAT=json"),
			pulumi.String("GF_SECURITY_ADMIN_USER=admin"),
			pulumi.String("GF_SECURITY_ADMIN_PASSWORD=" + secrets["GRAFANA_ADMIN_PASSWORD"]),
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
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	})
	if err != nil {
		return nil, nil, nil, err
	}

	return container, image, data, nil
}
