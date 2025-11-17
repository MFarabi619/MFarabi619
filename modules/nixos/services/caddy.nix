{
  pkgs,
  config,
  ...
}:
let
  # NOTE: enormous thanks to blog post: aottr.dev/posts/2024/08/homelab-setting-up-caddy-reverse-proxy-with-ssl-on-nixos/
  certloc = "/var/lib/acme/openws.org";
  tlsConfig = ''
    tls ${certloc}/cert.pem ${certloc}/key.pem {
      protocols tls1.3
    }
  '';
in
{
  services.caddy = {
    enable = true;
    email = "mfarabi619@gmail.com";

    virtualHosts = {
      "openws.org" = {
        extraConfig = ''
          root * /var/www/html
          file_server
          ${tlsConfig}
        '';
      };

      "docs.openws.org" = {
        extraConfig = ''
          root * /var/www/html/dist
          try_files {path} /index.html
          file_server
          header {
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            X-Frame-Options "DENY"
            X-Content-Type-Options "nosniff"
          }
          ${tlsConfig}
        '';
      };

      "ml.openws.org" = {
        extraConfig = ''
          reverse_proxy http://0.0.0.0:7777
          ${tlsConfig}
        '';
      };

      "mirror.openws.org" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.142
          ${tlsConfig}
        '';
      };

      "api.apidaesystems.ca" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.16
          ${tlsConfig}
        '';
      };

      "iot.apidaesystems.ca" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.16
          ${tlsConfig}
        '';
      };

      "tandemrobotics.ca" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:5150
          ${tlsConfig}
        '';
      };
    };
  };
}
