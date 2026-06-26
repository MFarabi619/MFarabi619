# See /modules/nixos/* for actual settings
# This file is just *top-level* configuration.
{
  flake,
  ...
}:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
rec {
  imports = [
    self.nixosModules.wsl
    self.nixosModules.default
    self.nixosModules.nixpkgs
  ];

  system.stateVersion = "25.05";
  networking.hostName = "nixos-wsl";
  nixpkgs.hostPlatform = "x86_64-linux";
  nixos-unified.sshTarget = networking.hostName;

  hardware.uinput.enable = true;

  services = {
    seatd.enable = true;
    qemuGuest.enable = true;
    spice-webdavd.enable = true;
    spice-vdagentd.enable = true;
  };

}
