{
  config,
  ...
}:
let
  # NOTE: enormous thanks to blog post: aottr.dev/posts/2024/08/homelab-setting-up-caddy-reverse-proxy-with-ssl-on-nixos/
  certloc = "/var/lib/acme/openws.org";
  # NOTE: TLS disabled as https is handled by cloudflare tunnel
  tlsConfig = ''
    # tls ${certloc}/cert.pem ${certloc}/key.pem {
    #   protocols tls1.3
    # }
  '';

  clientIp = ''
    header_up X-Forwarded-For {client_ip}
    header_up X-Real-IP {client_ip}
    header_up X-Http-Version {http.request.proto}

  '';
in
{
  services.caddy = {
    enable = true;
    email = "mfarabi619@gmail.com";
    # configFile = ./caddyfile

    globalConfig = ''
      metrics {
        per_host
      }

      servers {
        # Cloudflare IP ranges from https://www.cloudflare.com/en-gb/ips/
        trusted_proxies static 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32

        # Use CF-Connecting-IP to determine the client IP instead of XFF
        # https://caddyserver.com/docs/caddyfile/options#client-ip-headers
        client_ip_headers CF-Connecting-IP
      }
    '';

    virtualHosts = {
      # "http://openws.org" = {
      #   extraConfig = ''
      #     root * /var/www/html
      #     file_server
      #     ${tlsConfig}
      #   '';
      # };

      "http://openws.org" = {
        extraConfig = ''
          reverse_proxy http://${config.services.anubis.instances.index.settings.BIND} {
            ${clientIp}
          }
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
            ${clientIp}
          }
          ${tlsConfig}
        '';
      };

      "http://demo.openws.org" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1:7681 {
            ${clientIp}
          }
           ${tlsConfig}
        '';
      };

      "http://rpi5.openws.org" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.122:7681 {
            ${clientIp}
          }
           ${tlsConfig}
        '';
      };

      "http://mirror.openws.org" = {
        extraConfig = ''
          reverse_proxy http://${config.services.anubis.instances.mirror.settings.BIND} {
            ${clientIp}
          }
          ${tlsConfig}
        '';
      };

      "http://iot.apidaesystems.ca" = {
        extraConfig = ''
          reverse_proxy http://${config.services.anubis.instances.iot.settings.BIND} {
            ${clientIp}
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

      "http://freebsd.openws.org" = {
        extraConfig = ''
          reverse_proxy http://192.168.50.242:7681
          ${tlsConfig}
        '';
      };

      "http://tandemrobotics.ca" = {
        extraConfig = ''
          reverse_proxy http://127.0.0.1${config.services.anubis.instances.tandemrobotics.settings.BIND} {
            ${clientIp}
          }
          ${tlsConfig}
        '';
      };
    };
  };
}
