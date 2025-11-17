{
  config,
  ...
}:

{
  networking = {
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = builtins.concatLists [
        (if config.services.openssh.enable then [ 22 ] else [ ])
        (if config.services.netdata.enable then [ 19999 ] else [ ])
      ];

      allowedUDPPorts = [
        68 # DHCP
        546
      ];
    };
  };
}
