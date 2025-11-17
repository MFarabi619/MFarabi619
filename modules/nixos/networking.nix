{
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # nginx/caddy/traefik
        443
        5150 # loco
        7681 # ttyd
        19999 # netdata
      ];
      allowedUDPPorts = [
        68 # DHCP
        546
      ];
    };
  };
}
