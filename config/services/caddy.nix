{
  lib,
  config,
  ...
}:
{
  certificates = [ "*.localhost" ];
  services.caddy = {
    enable = true;
    config = ''
      {
        # auto_https off
        log default {
          level INFO
          output stdout
          format console
        }
      }
    '';

    virtualHosts = lib.mkMerge [
      # Simple proxies: name -> upstream
      (lib.mapAttrs'
        (
          name: upstream:
          lib.nameValuePair "${name}.localhost" {
            extraConfig = "reverse_proxy ${toString upstream}";
          }
        )
        {
          microvisor = "http://10.0.0.236";
        }
      )

      # Special-case vhosts
      {
        "web.localhost".extraConfig = ''
          log
          file_server
          encode zstd gzip
          root * ${config.git.root}/target/dx/web/release/web/public
          tls ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost.pem ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost-key.pem
        '';
      }
      {
        "tui.localhost".extraConfig = ''
          log
          file_server
          encode zstd gzip
          root * ${config.git.root}/tui/dist
          tls ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost.pem ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost-key.pem
        '';
      }

      (lib.optionalAttrs config.services.prometheus.enable {
        "prometheus.localhost".extraConfig = "reverse_proxy :${toString config.services.prometheus.port}";
      })
    ];
  };

  hosts = lib.genAttrs (lib.attrNames config.services.caddy.virtualHosts) (_: "127.0.0.1");
}
