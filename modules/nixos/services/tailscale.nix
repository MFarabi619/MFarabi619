{
  services.tailscale = {
    enable = true;
    permitCertUid = null;
    useRoutingFeatures = "both"; # one of "none", "client", "server", "both"
    authKeyFile = "/run/secrets/tailscale_key";
    # extraDaemonFlags = [ ];

    extraUpFlags = [
      "--ssh"
    ];

    # extraSetFlags = [
    #   "--advertise-exit-node"
    # ];

    # authKeyParameters = {
    #   baseURL = "";
    #   ephemeral = false;
    #   preauthorized = false;
    # };

    # derper = {
    #   enable = false;
    #   domain = "";
    #   port = 8010; # default
    #   stunPort = 3478;
    #   openFirewall = true;
    #   verifyClients = false;
    #   configureNginx = true;
    # };
  };
}
