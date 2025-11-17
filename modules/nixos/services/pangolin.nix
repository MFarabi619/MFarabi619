{
  services.traefik = {
    environmentFiles = [
      "/etc/cloudflared/.env"
    ];
  };

  services.pangolin = {
    enable = false;
    openFirewall = true;
    dnsProvider = "cloudflare";
    baseDomain = "openws.org";
    dataDir = "/var/lib/pangolin";
    # dashboardDomain = "pangolin.openws.org";
    # letsEncryptEmail = "mfarabi619@gmail.com";
    environmentFile = "/etc/cloudflared/.env";
    settings = {
      app = {
        save_logs = true;
      };
      gerbil = {
        base_endpoint = "YOUR_VPS_IP";
      };
      domains = {
        "openws.org" = {
          prefer_wildcard_cert = true;
        };
      };
      server = {
        external_port = 3007;
        internal_port = 3008;
      };
    };
  };
}
