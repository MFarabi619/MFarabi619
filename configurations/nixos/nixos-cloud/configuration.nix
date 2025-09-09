{ ... }:
{
  imports = [
    ./networking.nix # generated at runtime by nixos-infect
    ./hardware-configuration.nix
  ];

  zramSwap.enable = true;
  boot.tmp.cleanOnBoot = true;

  networking = {
    hostName = "nixos-cloud";
    domain = "";
  };

  services = {
    openssh.enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHX5kFcw6u7VABnRc2bg2MdOK4QssJnATEPvV84XynWD''
  ];

  system.stateVersion = "23.11";
}
