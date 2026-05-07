{
  flake,
  config,
  modulesPath,
  ...
}:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = with self.nixosModules; [
    boot
    disko
    users
    default
    containers
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking.hostName = "nixos";
  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "aarch64-linux";
  nixos-unified.sshTarget = config.networking.hostName;

  # Host-specific performance tunings. Migrate to shared modules
  # once validated and known-safe for framework-desktop.
  boot = {
    tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
    };

    kernel.sysctl = {
      "vm.swappiness" = 10;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
