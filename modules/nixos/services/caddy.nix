{
  lib,
  config,
  ...
}:
{
  # NOTE: enormous thanks to blog post: aottr.dev/posts/2024/08/homelab-setting-up-caddy-reverse-proxy-with-ssl-on-nixos/
  # certloc = "/var/lib/acme/openws.org";
  # # NOTE: TLS disabled as https is handled by cloudflare tunnel
  # tlsConfig = ''
  #   # tls ${certloc}/cert.pem ${certloc}/key.pem {
  #   #   protocols tls1.3
  #   # }
  # '';

  services.caddy = {
    email = config.security.acme.defaults.email;
    enable = config.networking.hostName == "framework-desktop";

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

    virtualHosts = lib.mkMerge [
      (lib.concatMapAttrs
        (
          domain: hosts:
          lib.mapAttrs' (
            name: upstream:
            lib.nameValuePair "http://${name}.${domain}" {
              extraConfig = ''
                reverse_proxy ${upstream}
              '';
            }
          ) hosts
        )
        {
          "openws.org" = {
            penpot = ":81";
            admin = ":1212";
            excalidraw = ":81";
            registry = ":5000";
            rpi5 = "rpi5-8:7681";
            emacs = "rpi5-8:7682";
            neovim = "rpi5-8:7683";
            freebsd = "msi-ge76:7681";
            mirror = config.services.anubis.instances.mirror.settings.TARGET;
          };

          "apidaesystems.ca" = {
            crm = ":81";
            portal = ":81";
            sentry = ":81";
            supabase = ":81";
            minio = "rpi5-16";
            horizon = "rpi5-8";
            registry = "rpi5-16";
            admin = "rpi5-16:3000";
            rutx11 = "100.111.144.127";
            ceratina = "http://rutx11:3000";
            halow = "http://halowlink2-6c7f";
          };
        }
      )
      # (lib.concatMapAttrs
      #   (
      #     domain: hosts:
      #     lib.mapAttrs' (
      #       name: upstream:
      #       lib.nameValuePair "http://${name}.${domain}" {
      #         extraConfig = ''
      #           reverse_proxy ${upstream} {
      #             transport http {
      #               tls_insecure_skip_verify
      #             }
      #           }
      #         '';
      #       }
      #     ) hosts
      #   )
      #   {
      #     "openws.org" = {
      #       proxmox = ":8006";
      #     };
      #   }
      # )
      (lib.mapAttrs'
        (
          name: upstream:
          lib.nameValuePair "http://${name}" {
            extraConfig = ''
              reverse_proxy ${upstream} {
                header_up X-Forwarded-For {client_ip}
                header_up X-Real-IP {client_ip}
                header_up X-Http-Version {http.request.proto}
              }
            '';
          }
        )
        {
          "microvisor.systems" = "http://10.0.0.236";
          "tandemrobotics.ca" = config.services.anubis.instances.tandemrobotics.settings.BIND;
        }
      )
      {
        "http://manzikert.ca".extraConfig = "reverse_proxy :81";
        "http://www.manzikert.ca".extraConfig = "reverse_proxy :81";
        "http://apidaesystems.ca".extraConfig = "redir https://www.apidaesystems.ca";

        "http://openws.org".extraConfig = ''
          reverse_proxy http://${config.services.anubis.instances.homepage-dashboard.settings.BIND} {
            header_up X-Forwarded-For {client_ip}
            header_up X-Real-IP {client_ip}
            header_up X-Http-Version {http.request.proto}
          }
        ''
        + lib.optionalString config.services.grafana.enable ''
          handle /grafana* {
            reverse_proxy :${toString config.services.grafana.settings.server.http_port}
          }
        ''
        + lib.optionalString config.services.plantuml-server.enable ''
          handle /plantuml* {
            reverse_proxy :${toString config.services.plantuml-server.listenPort}
          }
        '';

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
          '';
        };
      }
      (lib.optionalAttrs config.services.open-webui.enable {
        "http://ai.openws.org".extraConfig = ''
          reverse_proxy :${toString config.services.open-webui.port} {
            header_up X-Forwarded-For {client_ip}
            header_up X-Real-IP {client_ip}
            header_up X-Http-Version {http.request.proto}
          }
        '';
      })
      (lib.optionalAttrs config.services.ttyd.enable {
        "http://demo.openws.org".extraConfig = ''
          reverse_proxy :${toString config.services.ttyd.port} {
            header_up X-Forwarded-For {client_ip}
            header_up X-Real-IP {client_ip}
            header_up X-Http-Version {http.request.proto}
          }
        '';
      })
      (lib.optionalAttrs config.services.anki-sync-server.enable {
        "http://anki.microvisor.dev".extraConfig =
          "reverse_proxy :${toString config.services.anki-sync-server.port}";
      })
    ];
  };
}
