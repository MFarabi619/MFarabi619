{
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # nginx/caddy
        # 443
        5150 # loco
        19999 # netdata
      ];
      allowedUDPPorts = [
        68 # DHCP
        546
      ];
    };
  };
}
