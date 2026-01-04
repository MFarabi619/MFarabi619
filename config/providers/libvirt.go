// pulumi package add terraform-provider dmacvicar/libvirt
// go get github.com/pulumi/pulumi-terraform-provider/sdks/go/libvirt/libvirt
// brew services start libvirt

package providers

import (
	//   "github.com/pulumi/pulumi-terraform-provider/sdks/go/libvirt/libvirt"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func ProvisionVirtualMachine(ctx *pulumi.Context, enable bool) error {
	if !enable {
		return nil
	}

	// _, err := libvirt.NewDomain(ctx, "FreeBSD-15.0-STABLE", &libvirt.DomainArgs{
	// Name:       pulumi.String("FreeBSD-15.0-STABLE"),
	// Type:       pulumi.String("qemu"),
	// Memory:     pulumi.Float64(4096),
	// MemoryUnit: pulumi.String("MiB"),
	// Vcpu:       pulumi.Float64(4),
	// Running:    pulumi.Bool(true),

	// Os: &libvirt.DomainOsArgs{
	// 	Type:        pulumi.String("hvm"),
	// 	TypeArch:    pulumi.String("aarch64"),
	// 	TypeMachine: pulumi.String("virt"),
	// },

	// Devices: &libvirt.DomainDevicesArgs{
	// 	Disks: libvirt.DomainDevicesDiskArray{
	// 		&libvirt.DomainDevicesDiskArgs{
	// 			Source: &libvirt.DomainDevicesDiskSourceArgs{
	// 				File: &libvirt.DomainDevicesDiskSourceFileArgs{
	// 					File: pulumi.String("/Users/mfarabi/Downloads/iso/FreeBSD-15.0-STABLE-arm64-aarch64-zfs.qcow2"),
	// 				},
	// 			},
	// 			Target: &libvirt.DomainDevicesDiskTargetArgs{
	// 				Dev: pulumi.String("vda"),
	// 				Bus: pulumi.String("virtio"),
	// 			},
	// 		},
	// 	},
	// 	Interfaces: libvirt.DomainDevicesInterfaceArray{
	// 		&libvirt.DomainDevicesInterfaceArgs{
	// 			Model: &libvirt.DomainDevicesInterfaceModelArgs{
	// 				Type: pulumi.String("virtio"),
	// 			},
	// 			// 	Source: &libvirt.DomainDevicesInterfaceSourceArgs{
	// 			// 	Bridge: &libvirt.DomainDevicesInterfaceSourceBridgeArgs{
	// 			// 		Bridge: pulumi.String("bridge100"),
	// 			// 	},
	// 			// },
	// 			//	Source: &libvirt.DomainDevicesInterfaceSourceArgs{
	// 			//	User: &libvirt.DomainDevicesInterfaceSourceUserArgs{},
	// 			//	},
	// 		},
	// 	},

	// 	Graphics: libvirt.DomainDevicesGraphicArray{
	// 		&libvirt.DomainDevicesGraphicArgs{
	// 			//			Spice: &libvirt.DomainDevicesGraphicSpiceArgs{
	// 			//				AutoPort: pulumi.BoolPtr(true),
	// 			//				Listen:   pulumi.StringPtr("127.0.0.1"),
	// 			//			},
	// 			Vnc: &libvirt.DomainDevicesGraphicVncArgs{
	// 				AutoPort: pulumi.Bool(true),
	// 				Listen:   pulumi.String("127.0.0.1"),
	// 			},
	// 		},
	// 	},

	// 	Videos: libvirt.DomainDevicesVideoArray{
	// 		&libvirt.DomainDevicesVideoArgs{
	// 			Model: &libvirt.DomainDevicesVideoModelArgs{
	// 				Type: pulumi.StringPtr("virtio"),
	// 			},
	// 		},
	// 	},

	// 	Controllers: libvirt.DomainDevicesControllerArray{
	// 		&libvirt.DomainDevicesControllerArgs{
	// 			Type:  pulumi.String("usb"),
	// 			Model: pulumi.String("qemu-xhci"),
	// 		},
	// 	},

	// 	Inputs: libvirt.DomainDevicesInputTypeArray{
	// 		&libvirt.DomainDevicesInputTypeArgs{
	// 			Type: pulumi.String("tablet"),
	// 			Bus:  pulumi.String("usb"),
	// 		},
	// 		&libvirt.DomainDevicesInputTypeArgs{
	// 			Type: pulumi.String("keyboard"),
	// 			Bus:  pulumi.String("usb"),
	// 		},
	// 		&libvirt.DomainDevicesInputTypeArgs{
	// 			Type: pulumi.String("mouse"),
	// 			Bus:  pulumi.String("usb"),
	// 		},
	// 	},

	// 	Serials: libvirt.DomainDevicesSerialArray{
	// 		&libvirt.DomainDevicesSerialArgs{
	// 			Source: &libvirt.DomainDevicesSerialSourceArgs{
	// 				Unix: &libvirt.DomainDevicesSerialSourceUnixArgs{
	// 					Path: pulumi.String("/Users/mfarabi/.cache/libvirt/virsh/FreeBSD-15.0-STABLE-arm64-aarch64-zfs.sock"),
	// 					Mode: pulumi.String("bind"),
	// 				},
	// 			},
	// 			Target: &libvirt.DomainDevicesSerialTargetArgs{
	// 				Port: pulumi.Float64(0),
	// 			},
	// 		},
	// 	},

	// 	Consoles: libvirt.DomainDevicesConsoleArray{
	// 		&libvirt.DomainDevicesConsoleArgs{
	// 			Source: &libvirt.DomainDevicesConsoleSourceArgs{
	// 				Unix: &libvirt.DomainDevicesConsoleSourceUnixArgs{
	// 					Path: pulumi.String("/Users/mfarabi/.cache/libvirt/virsh/FreeBSD-15.0-STABLE-arm64-aarch64-zfs-console.sock"),
	// 					Mode: pulumi.String("bind"),
	// 				},
	// 			},
	// 			Target: &libvirt.DomainDevicesConsoleTargetArgs{
	// 				Type: pulumi.String("serial"),
	// 				Port: pulumi.Float64(0),
	// 			},
	// 		},
	// 	},
	// },
	// })

	// if err != nil {
	// return err
	//}

	// return err
	return nil
}
