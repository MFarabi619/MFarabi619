{
  services = {
    nginx = {
      enable = true;
      virtualHosts."_" = {
        default = true;
        root = "/var/www/html";
        locations."/" = {
          index = "index.html";
        };

        listen = [
          {
            addr = "127.0.0.1";
            port = 80;
          }

        ];
      };
    };

    caddy = {
      enable = false; # FIXME: getting redirected too many times on cloudflare
      user = "caddy"; # default
      group = "caddy"; # default
      enableReload = true; # default
      logDir = "/var/log/caddy"; # default
      dataDir = "/var/lib/caddy"; # default
      # email = "mfarabi619@gmail.com";
      virtualHosts = {
        "localhost" = {
          # listenAddresses = [
          #   "127.0.0.1"
          #   # "::80"
          # ];
          extraConfig = ''
            encode gzip
            file_server
            root * /var/www/html
          '';
        };
      };
    };
  };
}
