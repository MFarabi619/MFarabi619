{
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        # 80 # caddy
        # 443
        19999 # netdata
      ];
      allowedUDPPorts = [
        68 # DHCP
        546
      ];
    };
  };
}
