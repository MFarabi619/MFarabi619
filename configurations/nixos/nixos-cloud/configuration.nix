{ config, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos-cloud";
  system.stateVersion = "25.11";
  nixos-unified.sshTarget = config.networking.hostName;

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
