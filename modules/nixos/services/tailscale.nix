{
  services.tailscale = {
    enable = true;
    openFirewall = false;
    port = 41641; # default
    permitCertUid = null;
    disableTaildrop = false;
    useRoutingFeatures = "both"; # one of "none", "client", "server", "both"
    interfaceName = "tailscale0"; # default
    authKeyFile = "/run/secrets/tailscale_key";
    # extraDaemonFlags = [ ];
    extraUpFlags = [
      "--ssh"
    ];
    extraSetFlags = [
      "--advertise-exit-node"
    ];
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
