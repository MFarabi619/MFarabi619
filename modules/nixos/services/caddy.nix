let
  # NOTE: enormous thanks to blog post: aottr.dev/posts/2024/08/homelab-setting-up-caddy-reverse-proxy-with-ssl-on-nixos/
  certloc = "/var/lib/acme/openws.org";
  # NOTE: TLS disabled as https is handled by cloudflare tunnel
  tlsConfig = ''
    # tls ${certloc}/cert.pem ${certloc}/key.pem {
    #   protocols tls1.3
    # }
  '';
in
{
  services.caddy = {
    enable = true;
    email = "mfarabi619@gmail.com";

    virtualHosts = {
      "http://openws.org" = {
        extraConfig = ''
          root * /var/www/html
          file_server
          ${tlsConfig}
        '';
      };

      "http://docs.openws.org" = {
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

      "http://ai.openws.org" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:7777 {
            header_down X-Real-IP {http.request.remote}
            header_down X-Forwarded-For {http.request.remote}
          }
          ${tlsConfig}
        '';
      };

      "http://demo.openws.org" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:7681
           ${tlsConfig}
        '';
      };

      "http://mirror.openws.org" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.142
          ${tlsConfig}
        '';
      };

      "http://iot.apidaesystems.ca" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:8080 {
            header_down X-Real-IP {http.request.remote}
            header_down X-Forwarded-For {http.request.remote}
          }
          ${tlsConfig}
        '';
      };

      "http://demo.apidaesystems.ca" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.16
          ${tlsConfig}
        '';
      };

      "http://tandemrobotics.ca" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:5150 {
            header_down X-Real-IP {http.request.remote}
            header_down X-Forwarded-For {http.request.remote}
          }
          ${tlsConfig}
        '';
      };
    };
  };
}
