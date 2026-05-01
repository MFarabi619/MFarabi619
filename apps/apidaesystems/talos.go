// pulumi plugin install resource talos --server github://api.github.com/pulumiverse
// go get github.com/pulumiverse/pulumi-talos/sdk/go/talos
// go get github.com/pulumi/pulumi-command/sdk/go/command/local
//
// Prereqs (manual, one-time):
//   1. `talosctl` installed on the host running `pulumi up`. Latest:
//        https://github.com/siderolabs/talos/releases
//   2. Boot a Talos VM (UTM, bare metal, cloud — anywhere) from the official
//      Talos ISO. Eject the ISO after first install completes; otherwise
//      `talos.halt_if_installed` halts subsequent boots from CDROM.
//   3. Note (or pin via DHCP) the VM's IP, set it in Pulumi.yaml under
//      `local:talos.nodeIP` / `local:talos.endpoint`.
//
// ─── Why we shell out to talosctl instead of using native resources ───
//
// terraform-provider-talos `machine_configuration_apply` has an open bug
// (since 2025-06): the gRPC call returns success in <1s without writing
// config to the node, leaving Bootstrap to fail with PermissionDenied.
//   - https://github.com/siderolabs/terraform-provider-talos/issues/265
//
// pulumi-talos v0.7.1 wraps TF-talos v0.10.1; upstream is at v0.11.0 but
// the bridge bump is not yet shipped.
//   - https://github.com/pulumiverse/pulumi-talos/issues/239
//
// We keep the parts that work (Secrets, GetConfiguration, LookupKubeconfig,
// client.GetConfiguration) and replace the broken ConfigurationApply +
// Bootstrap with `local.Command` resources around talosctl. Lifecycle stays
// in the Pulumi graph: Triggers re-run apply when config changes; Delete
// resets the node so `pulumi destroy` returns the disk to maintenance mode.
//
// TalosVersion is pinned to "v1.12.0" because that's the schema bundled
// with pulumi-talos v0.7.1's machinery. Newer apids accept older config
// schemas without complaint, so this is forward-safe; revisit when issue
// #239 ships and we move to v0.11.0 (machinery v1.13.0).

package main

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-talos/sdk/go/talos/client"
	"github.com/pulumiverse/pulumi-talos/sdk/go/talos/cluster"
	"github.com/pulumiverse/pulumi-talos/sdk/go/talos/machine"
)

// createTalos provisions a single-node Talos Linux Kubernetes cluster.
//
// Single-node design: the controlplane is also a worker
// (allowSchedulingOnControlPlanes=true). For homelab/dev this is the right
// tradeoff — three VMs of overhead buys nothing here.
//
// `diskSelector: size: ">10GB"` works regardless of disk naming
// (`/dev/sda` vs `/dev/vda` vs `/dev/nvme0n1`); valid `type` values are
// `ssd|hdd|nvme|sd`, but omitting `type` matches any non-removable block
// device. Source:
// https://github.com/siderolabs/talos/blob/v1.13.0/pkg/machinery/config/types/v1alpha1/v1alpha1_types.go#L992-L1029
//
// Returns the LookupKubeconfig output so callers can feed KubeconfigRaw()
// into a kubernetes.Provider for downstream Helm releases / manifests.
func createTalos(ctx *pulumi.Context, nodeIP, endpoint string) (cluster.LookupKubeconfigResultOutput, error) {
	secrets, err := machine.NewSecrets(ctx, "apidae-secrets", &machine.SecretsArgs{})
	if err != nil {
		return cluster.LookupKubeconfigResultOutput{}, err
	}

	cpConfig := machine.GetConfigurationOutput(ctx, machine.GetConfigurationOutputArgs{
		ClusterName:     pulumi.String("apidae"),
		MachineType:     pulumi.String("controlplane"),
		ClusterEndpoint: pulumi.Sprintf("https://%s:6443", endpoint),
		MachineSecrets:  secrets.MachineSecrets,
		TalosVersion:    pulumi.String("v1.12.0"),
		ConfigPatches: pulumi.StringArray{
			pulumi.String(`{"cluster":{"allowSchedulingOnControlPlanes":true}}`),
			pulumi.String(`{"machine":{"install":{"diskSelector":{"size":">10GB"}}}}`),
		},
	}, nil)

	talosClientCfg := client.GetConfigurationClientConfigurationArgs{
		CaCertificate:     secrets.ClientConfiguration.CaCertificate(),
		ClientCertificate: secrets.ClientConfiguration.ClientCertificate(),
		ClientKey:         secrets.ClientConfiguration.ClientKey(),
	}

	talosCfg := client.GetConfigurationOutput(ctx, client.GetConfigurationOutputArgs{
		ClusterName:         pulumi.String("apidae"),
		ClientConfiguration: talosClientCfg,
		Endpoints:           pulumi.StringArray{pulumi.String(endpoint)},
		Nodes:               pulumi.StringArray{pulumi.String(nodeIP)},
	}, nil)

	// On `pulumi destroy`, Delete runs `talosctl reset` to wipe STATE +
	// EPHEMERAL partitions and reboot into maintenance mode. Without this,
	// a destroy-then-up cycle would fail at bootstrap with AlreadyExists
	// because etcd would still be initialized on disk.
	//
	// Inline `bash -c` (instead of Stdin) because pulumi-command's Stdin is
	// shared across Create/Delete phases — Create already uses Stdin to
	// pipe the rendered config, so Delete needs its own self-contained
	// shell. The Go raw string (backticks) lets bash own the inner quotes
	// without escaping. `|| true` swallows errors from already-reset nodes
	// so a second `pulumi destroy` is idempotent.
	deleteCmd := `bash -c 'TC=$(mktemp); printf "%s" "$TALOSCONFIG_DATA" > "$TC"; ` +
		`talosctl --talosconfig="$TC" --nodes ` + nodeIP + ` --endpoints ` + endpoint +
		` reset --graceful=false --reboot --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL || true; ` +
		`rm -f "$TC"'`

	// Dual-mode apply: handles both maintenance-mode (first-ever provisioning,
	// node has no cluster CA yet) and authenticated mode (post-bootstrap,
	// apid demands client cert). Probe with `talosctl version` against the
	// authenticated apid; if it responds, apply-config with --mode=auto (no
	// reboot needed for most config changes); otherwise fall through to
	// --insecure for maintenance-mode bootstrap.
	//
	// This makes the resource re-create-safe: changing the Pulumi resource
	// definition (e.g. adding Delete) replaces the resource, which re-runs
	// Create — which now correctly handles a bootstrapped node.
	applyScript := `set -eu
TC=$(mktemp)
trap 'rm -f "$TC"' EXIT
printf '%s' "$TALOSCONFIG_DATA" > "$TC"
CFG=$(mktemp)
trap 'rm -f "$TC" "$CFG"' EXIT
cat > "$CFG"
if talosctl --talosconfig="$TC" --nodes ` + nodeIP + ` --endpoints ` + endpoint + ` version >/dev/null 2>&1; then
  echo "node is bootstrapped, using authenticated apply-config" >&2
  talosctl --talosconfig="$TC" --nodes ` + nodeIP + ` --endpoints ` + endpoint + ` apply-config --file "$CFG" --mode auto
else
  echo "node is in maintenance mode, using --insecure" >&2
  talosctl apply-config --insecure --nodes ` + nodeIP + ` --file "$CFG"
fi
`

	// `bash -c "$APPLY_SCRIPT"` — outer sh expands APPLY_SCRIPT (multi-line)
	// into bash's -c argument; rendered config flows through Stdin and gets
	// captured inside the script via `cat > "$CFG"`.
	applyCmd, err := local.NewCommand(ctx, "apidae-cp-apply", &local.CommandArgs{
		Create: pulumi.String(`bash -c "$APPLY_SCRIPT"`),
		Update: pulumi.String(`bash -c "$APPLY_SCRIPT"`),
		Stdin:  cpConfig.MachineConfiguration(),
		Delete: pulumi.String(deleteCmd),
		Environment: pulumi.StringMap{
			"TALOSCONFIG_DATA": talosCfg.TalosConfig(),
			"APPLY_SCRIPT":     pulumi.String(applyScript),
		},
		Triggers: pulumi.Array{
			cpConfig.MachineConfiguration(),
		},
	})
	if err != nil {
		return cluster.LookupKubeconfigResultOutput{}, err
	}

	// Bootstrap script:
	//   1. write talosconfig to a tempfile (sensitive — never on argv)
	//   2. poll `talosctl version` until apid responds on the cluster cert
	//      (post-install reboot, ~30-60s)
	//   3. fail loudly if apid never came up — silent fallthrough hides bugs
	//   4. run bootstrap; tolerate AlreadyExists so re-runs after partial
	//      failures or destroy-without-reset cycles don't hard-fail
	bootstrapScript := `set -eu
TC=$(mktemp)
trap 'rm -f "$TC"' EXIT
printf '%s' "$TALOSCONFIG_DATA" > "$TC"
for i in $(seq 1 60); do
  talosctl --talosconfig="$TC" --nodes ` + nodeIP + ` --endpoints ` + endpoint + ` version >/dev/null 2>&1 && break
  if [ "$i" = "60" ]; then
    echo "apid never came up after 5min on ` + nodeIP + `" >&2
    exit 1
  fi
  sleep 5
done
out=$(talosctl --talosconfig="$TC" --nodes ` + nodeIP + ` --endpoints ` + endpoint + ` bootstrap 2>&1) || {
  echo "$out" | grep -qi "AlreadyExists" && { echo "etcd already bootstrapped, ok" >&2; exit 0; }
  echo "$out" >&2
  exit 1
}
`

	bootstrapCmd, err := local.NewCommand(ctx, "apidae-bootstrap", &local.CommandArgs{
		Create: pulumi.String("bash"),
		Stdin:  pulumi.String(bootstrapScript),
		Environment: pulumi.StringMap{
			"TALOSCONFIG_DATA": talosCfg.TalosConfig(),
		},
	}, pulumi.DependsOn([]pulumi.Resource{applyCmd}))
	if err != nil {
		return cluster.LookupKubeconfigResultOutput{}, err
	}

	kubeconfigClientCfg := cluster.GetKubeconfigClientConfigurationArgs{
		CaCertificate:     secrets.ClientConfiguration.CaCertificate(),
		ClientCertificate: secrets.ClientConfiguration.ClientCertificate(),
		ClientKey:         secrets.ClientConfiguration.ClientKey(),
	}

	kubeconfig := cluster.LookupKubeconfigOutput(ctx, cluster.LookupKubeconfigOutputArgs{
		ClientConfiguration: kubeconfigClientCfg,
		Node:                pulumi.String(nodeIP),
		Endpoint:            pulumi.String(endpoint),
	}, pulumi.Parent(bootstrapCmd))

	ctx.Export("talos:kubeconfig", pulumi.ToSecret(kubeconfig.KubeconfigRaw()))
	ctx.Export("talos:talosconfig", pulumi.ToSecret(talosCfg.TalosConfig()))

	return kubeconfig, nil
}
