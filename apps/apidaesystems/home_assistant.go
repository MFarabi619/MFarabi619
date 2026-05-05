package main

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

const homeAssistantServiceYAML = `    - Home Assistant:
        href: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        siteMonitor: https://home-assistant.{{HOMEPAGE_VAR_DOMAIN}}
        icon: home-assistant.svg
        server: local
        container: home-assistant
        widget:
          type: homeassistant
          url: http://home-assistant:8123
          key: "{{HOMEPAGE_VAR_HA_ACCESS_TOKEN}}"
`

// createHomeAssistant provisions the HA container. mqttBroker is taken as a
// dependency (so HA starts after the broker is up) but the broker connection
// itself must be configured via HA's UI integration flow — Settings →
// Devices & Services → Add Integration → MQTT — because HA dropped YAML-based
// broker config in 2022.12. After that one-time UI step, the firmware's
// `homeassistant/sensor/.../config` discovery messages auto-populate entities.
func createHomeAssistant(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, domain string, settings serviceConfig, mqttBroker *docker.Container) (*docker.Container, error) {
	homeAssistantConfig, err := createVolume(ctx, "home-assistant-config")
	if err != nil {
		return nil, err
	}

	image, err := pullImage(ctx, "home-assistant", settings.Image)
	if err != nil {
		return nil, err
	}

	configuration := map[string]any{
		"default_config": nil,
		"homeassistant": map[string]any{
			"name":        "Apidae Systems",
			"latitude":    43.6532,
			"longitude":   -79.3832,
			"elevation":   76,
			"unit_system": "metric",
			"time_zone":   "America/Toronto",
			"country":     "CA",
			"language":    "en",
			"currency":    "CAD",
		},
		"http": map[string]any{
			"use_x_forwarded_for": true,
			"trusted_proxies":     []string{"172.18.0.0/16"},
		},
		"recorder": map[string]any{
			"auto_purge":      true,
			"purge_keep_days": 10,
		},
		"history": nil,
	}

	var resourceOptions []pulumi.ResourceOption
	if mqttBroker != nil {
		resourceOptions = append(resourceOptions, pulumi.DependsOn([]pulumi.Resource{mqttBroker}))
	}
	configYAML, err := yaml.Marshal(configuration)
	if err != nil {
		return nil, err
	}

	container, err := docker.NewContainer(ctx, "home-assistant", &docker.ContainerArgs{
		Image:               image.ImageId,
		Name:                pulumi.String("home-assistant"),
		Hostname:            pulumi.String("home-assistant"),
		Restart:             pulumi.String("unless-stopped"),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(512),
		DestroyGraceSeconds: pulumi.Int(10),
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
			Adds: pulumi.StringArray{
				pulumi.String("CHOWN"),
				pulumi.String("SETUID"),
				pulumi.String("SETGID"),
				pulumi.String("DAC_OVERRIDE"),
				pulumi.String("FOWNER"),
				pulumi.String("NET_RAW"),
			},
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Uploads: docker.ContainerUploadArray{
			&docker.ContainerUploadArgs{
				File:    pulumi.String("/config/configuration.yaml"),
				Content: pulumi.String(string(configYAML)),
			},
		},
		Labels: createTraefikLabels("home-assistant", "home-assistant."+domain, "8123"),
		Envs: pulumi.StringArray{
			pulumi.String("TZ=America/Toronto"),
		},
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    homeAssistantConfig.Name,
				ContainerPath: pulumi.String("/config"),
			},
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("wget --no-verbose --tries=1 --spider http://localhost:8123 || exit 1"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("5s"),
			Retries:     pulumi.Int(3),
			StartPeriod: pulumi.String("30s"),
		},
	}, resourceOptions...)
	if err != nil {
		return nil, err
	}

	ctx.Export("home-assistant image", image.RepoDigest)
	ctx.Export("home-assistant id", container.ID())
	ctx.Export("home-assistant config", homeAssistantConfig.Mountpoint)

	onboardingScript := `#!/bin/sh
set -eu
RUN="docker run --rm --network=proxy curlimages/curl:8.10.0"
post() {
  step=$1; shift
  body=$1; shift
  resp=$($RUN -s -o /tmp/ha-resp -w "%{http_code}" -X POST -H "$auth" -H "Content-Type: application/json" -d "$body" "http://home-assistant:8123/api/onboarding/$step")
  case "$resp" in
    2*) ;;
    *) echo "step $step failed: HTTP $resp $(cat /tmp/ha-resp 2>/dev/null)" >&2; exit 1 ;;
  esac
}
ready=0
for attempt in $(seq 1 60); do
  status=$($RUN -sf -o /dev/null -w "%{http_code}" http://home-assistant:8123/api/onboarding || echo 000)
  case "$status" in 200) ready=1; break;; esac
  sleep 2
done
if [ "$ready" != "1" ]; then
  echo "home-assistant did not respond on /api/onboarding within 120s" >&2
  exit 1
fi
done_user=$($RUN -s http://home-assistant:8123/api/onboarding | grep -o '"step":"user"[^}]*"done":true' || true)
if [ -n "$done_user" ]; then
  echo "onboarding already complete"
  exit 0
fi
resp=$($RUN -s -X POST -H "Content-Type: application/json" \
  -d "{\"client_id\":\"http://home-assistant:8123/\",\"name\":\"Owner\",\"username\":\"$HOME_ASSISTANT_USERNAME\",\"password\":\"$HOME_ASSISTANT_PASSWORD\",\"language\":\"en\"}" \
  http://home-assistant:8123/api/onboarding/users)
code=$(echo "$resp" | sed -n 's/.*"auth_code":"\([^"]*\)".*/\1/p')
if [ -z "$code" ]; then
  echo "users step response: $resp" >&2
  exit 1
fi
token_resp=$($RUN -s -X POST \
  --data-urlencode "client_id=http://home-assistant:8123/" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$code" \
  http://home-assistant:8123/auth/token)
access=$(echo "$token_resp" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
if [ -z "$access" ]; then
  echo "/auth/token did not return an access_token: $token_resp" >&2
  exit 1
fi
auth="Authorization: Bearer $access"
post core_config '{}'
post analytics '{}'
post integration "{\"client_id\":\"http://home-assistant:8123/\",\"redirect_uri\":\"http://home-assistant:8123/?auth_callback=1\"}"
echo "onboarding complete"
`

	if _, err := local.NewCommand(ctx, "home-assistant-onboarding", &local.CommandArgs{
		Create: pulumi.String(onboardingScript),
		Update: pulumi.String(onboardingScript),
		Environment: pulumi.StringMap{
			"HOME_ASSISTANT_USERNAME": pulumi.String(secrets["HOME_ASSISTANT_USERNAME"]),
			"HOME_ASSISTANT_PASSWORD": pulumi.String(secrets["HOME_ASSISTANT_PASSWORD"]),
		},
		Triggers: pulumi.Array{container.ID()},
	}, pulumi.DependsOn([]pulumi.Resource{container}), pulumi.AdditionalSecretOutputs([]string{"environment", "stdout", "stderr"})); err != nil {
		return nil, err
	}

	return container, nil
}
