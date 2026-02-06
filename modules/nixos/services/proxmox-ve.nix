{
  lib,
  flake,
  config,
  ...
}:
{
  imports = [
    flake.inputs.proxmox-nixos.nixosModules.proxmox-ve
  ];

  services.proxmox-ve = {
    bridges = [ "vmbr0" ];
    ipAddress = "192.168.100.1";
    enable = config.networking.hostName == "framework-desktop";
  };

  nixpkgs.overlays = [
    flake.inputs.proxmox-nixos.overlays.${config.nixpkgs.hostPlatform.system}
    # HACK: otherwise tailscale ssh fails with 'Authentication Error'
    # See https://github.com/SaumonNet/proxmox-nixos/issues/70
    (self: super: {
      proxmox-ve = super.proxmox-ve.override (previous: {
        util-linux = previous.wget;
      });
    })
  ];

  networking = {
    bridges.vmbr0.interfaces = [ "enp191s0" ];
    interfaces.vmbr0.useDHCP = lib.mkDefault true;
  };
}
