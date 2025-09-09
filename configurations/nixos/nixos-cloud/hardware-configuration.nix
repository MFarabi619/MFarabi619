{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  fileSystems = {
    "/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/227C-A484";
      fsType = "vfat";
    };
  };

  boot = {
    loader.grub = {
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    initrd = {
      availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "vmw_pvscsi"
        "xen_blkfront"
      ];
      kernelModules = [ "nvme" ];
    };
  };

}
