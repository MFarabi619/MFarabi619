package e2e

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/auto"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const colimaSocket = "unix:///Users/mfarabi/.colima/default/docker.sock"

func zenohFabric(dockerContext string) pulumi.RunFunc {
	return func(ctx *pulumi.Context) error {
		network, err := docker.NewNetwork(ctx, "zenoh-fabric", &docker.NetworkArgs{
			Name: pulumi.String("zenoh-fabric"),
		})
		if err != nil {
			return err
		}

		nodeImage, err := docker.NewImage(ctx, "rmw-zenoh", &docker.ImageArgs{
			Build: &docker.DockerBuildArgs{
				Context:    pulumi.String(dockerContext),
				Dockerfile: pulumi.String(filepath.Join(dockerContext, "Dockerfile")),
			},
			ImageName: pulumi.String("rmw-zenoh:test"),
			SkipPush:  pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		routerImage, err := docker.NewRemoteImage(ctx, "zenoh-router-image", &docker.RemoteImageArgs{
			Name:        pulumi.String("eclipse/zenoh:latest"),
			KeepLocally: pulumi.Bool(true),
		})
		if err != nil {
			return err
		}

		attach := docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{Name: network.Name},
		}

		router, err := docker.NewContainer(ctx, "zenoh-router", &docker.ContainerArgs{
			Image:            routerImage.ImageId,
			Name:             pulumi.String("zenoh-router"),
			Restart:          pulumi.String("unless-stopped"),
			NetworksAdvanced: attach,
		})
		if err != nil {
			return err
		}

		zenohEnv := pulumi.StringArray{
			pulumi.String("RMW_IMPLEMENTATION=rmw_zenoh_cpp"),
			pulumi.String(`ZENOH_CONFIG_OVERRIDE=mode="client";connect/endpoints=["tcp/zenoh-router:7447"]`),
		}
		routerReady := pulumi.DependsOn([]pulumi.Resource{router})

		_, err = docker.NewContainer(ctx, "zenoh-talker", &docker.ContainerArgs{
			Image:   nodeImage.ImageName,
			Name:    pulumi.String("zenoh-talker"),
			Restart: pulumi.String("unless-stopped"),
			Envs:    zenohEnv,
			Command: pulumi.StringArray{
				pulumi.String("ros2"),
				pulumi.String("topic"),
				pulumi.String("pub"),
				pulumi.String("-r"),
				pulumi.String("1"),
				pulumi.String("/chatter"),
				pulumi.String("std_msgs/msg/String"),
				pulumi.String("{data: 'hello from pulumi'}"),
			},
			NetworksAdvanced: attach,
		}, routerReady)
		if err != nil {
			return err
		}

		_, err = docker.NewContainer(ctx, "zenoh-listener", &docker.ContainerArgs{
			Image:   nodeImage.ImageName,
			Name:    pulumi.String("zenoh-listener"),
			Restart: pulumi.String("unless-stopped"),
			Envs:    zenohEnv,
			Command: pulumi.StringArray{
				pulumi.String("ros2"),
				pulumi.String("topic"),
				pulumi.String("echo"),
				pulumi.String("/chatter"),
			},
			NetworksAdvanced: attach,
		}, routerReady)

		return err
	}
}

func listenerHeardMessage() bool {
	logs := exec.Command("docker", "logs", "zenoh-listener")
	logs.Env = append(os.Environ(), "DOCKER_HOST="+colimaSocket)
	out, _ := logs.CombinedOutput()
	return bytes.Contains(out, []byte("hello from pulumi"))
}

func TestZenohFabric(t *testing.T) {
	if testing.Short() {
		t.Skip("deploys real containers over docker; skipped under -short")
	}

	ctx := context.Background()
	dockerContext, err := filepath.Abs("testdata/rmw-zenoh")
	if err != nil {
		t.Fatal(err)
	}

	stack, err := auto.UpsertStackInlineSource(ctx, "test", "zenoh-fabric", zenohFabric(dockerContext))
	if err != nil {
		t.Fatalf("create stack: %v", err)
	}
	if err := stack.SetConfig(ctx, "docker:host", auto.ConfigValue{Value: colimaSocket}); err != nil {
		t.Fatalf("set docker:host: %v", err)
	}
	t.Cleanup(func() {
		if _, err := stack.Destroy(ctx); err != nil {
			t.Errorf("destroy: %v", err)
		}
	})

	if _, err := stack.Up(ctx); err != nil {
		t.Fatalf("up: %v", err)
	}

	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		if listenerHeardMessage() {
			return
		}
		time.Sleep(2 * time.Second)
	}
	t.Fatal("zenoh-listener never received the message over the router")
}
