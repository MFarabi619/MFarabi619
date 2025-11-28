package providers

import (
	"github.com/pulumi/pulumi-oci/sdk/v3/go/oci/core"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func SetupOracleCloud(ctx *pulumi.Context, enable bool) error {

	cfg := config.New(ctx, "")
	subnetId := cfg.Get("oci:subnetId")
	tenancyOcid := cfg.GetSecret("oci:tenancyOcid")

	if !enable {
		return nil
	}

	_, err := core.NewInstance(ctx, "ubuntu", &core.InstanceArgs{
		AvailabilityDomain: pulumi.String("famX:CA-MONTREAL-1-AD-1"),
		CompartmentId:      tenancyOcid,
		DisplayName:        pulumi.String("ubuntu-s-1vcpu-1gb-50gb-mon1-01"),
		FaultDomain:        pulumi.String("FAULT-DOMAIN-2"),

		AgentConfig: &core.InstanceAgentConfigArgs{
			PluginsConfigs: core.InstanceAgentConfigPluginsConfigArray{
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Vulnerability Scanning"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Management Agent"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Custom Logs Monitoring"),
					DesiredState: pulumi.String("ENABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Compute RDMA GPU Monitoring"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Compute Instance Monitoring"),
					DesiredState: pulumi.String("ENABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Compute HPC RDMA Auto-Configuration"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Compute HPC RDMA Authentication"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Cloud Guard Workload Protection"),
					DesiredState: pulumi.String("ENABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Block Volume Management"),
					DesiredState: pulumi.String("DISABLED"),
				},
				&core.InstanceAgentConfigPluginsConfigArgs{
					Name:         pulumi.String("Bastion"),
					DesiredState: pulumi.String("DISABLED"),
				},
			},
		},

		AvailabilityConfig: &core.InstanceAvailabilityConfigArgs{
			RecoveryAction: pulumi.String("RESTORE_INSTANCE"),
		},

		CreateVnicDetails: &core.InstanceCreateVnicDetailsArgs{
			DisplayName:   pulumi.String("ubuntu-s-1vcpu-1gb-50gb-mon1-01"),
			HostnameLabel: pulumi.String("ubuntu-s-1vcpu-1gb-50gb-mon1-01"),
			PrivateIp:     pulumi.String("10.0.0.63"),
			SubnetId:      pulumi.String(subnetId),
			DefinedTags: pulumi.StringMap{
				"Oracle-Tags.CreatedBy": pulumi.String("default/mfarabi619@gmail.com"),
				"Oracle-Tags.CreatedOn": pulumi.String("2025-11-28T05:54:02.799Z"),
			},
		},

		SourceDetails: &core.InstanceSourceDetailsArgs{
			SourceId:            pulumi.String("ocid1.image.oc1.ca-montreal-1.aaaaaaaauvqxdsotwl6auexnfvnvgpbseoong62njaoezz6l37umn5uryajq"),
			SourceType:          pulumi.String("image"),
			BootVolumeSizeInGbs: pulumi.String("47"),
			BootVolumeVpusPerGb: pulumi.String("10"),
		},

		Metadata: pulumi.StringMap{
			"ssh_authorized_keys": pulumi.String("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKz3Y58uXWAd7qPUfm+pcEPfCw484gt9Agjl+0hmZuU3 mfarabi@macos"),
		},

		ShapeConfig: &core.InstanceShapeConfigArgs{
			MemoryInGbs: pulumi.Float64(1),
			Ocpus:       pulumi.Float64(1),
			Vcpus:       pulumi.Int(2),
		},

		LaunchOptions: &core.InstanceLaunchOptionsArgs{
			BootVolumeType:                  pulumi.String("PARAVIRTUALIZED"),
			Firmware:                        pulumi.String("UEFI_64"),
			IsConsistentVolumeNamingEnabled: pulumi.Bool(true),
			IsPvEncryptionInTransitEnabled:  pulumi.Bool(true),
			NetworkType:                     pulumi.String("PARAVIRTUALIZED"),
			RemoteDataVolumeType:            pulumi.String("PARAVIRTUALIZED"),
		},

		DefinedTags: pulumi.StringMap{
			"Oracle-Tags.CreatedBy": pulumi.String("default/mfarabi619@gmail.com"),
			"Oracle-Tags.CreatedOn": pulumi.String("2025-11-28T05:54:02.722Z"),
		},

		State: pulumi.String("RUNNING"),
	}, pulumi.Protect(false))

	if err != nil {
		return err
	}

	return err
}
