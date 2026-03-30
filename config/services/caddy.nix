{
  lib,
  config,
  ...
}:

let
  common = ''
    log
    encode zstd gzip
    tls ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost.pem ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost-key.pem
  '';
in
{
  certificates = [ "*.localhost" ];
  hosts = lib.genAttrs (lib.attrNames config.services.caddy.virtualHosts) (_: "127.0.0.1");

  services.caddy = {
    enable = true;
    config = ''
      {
        log default {
          level INFO
          output stdout
          format console
        }
      }
    '';

    virtualHosts = lib.mkMerge [
      (lib.mapAttrs'
        (
          name: upstream:
          lib.nameValuePair "${name}.localhost" {
            extraConfig = ''
              ${common}
              reverse_proxy ${toString upstream}
            '';
          }
        )
        (
          {
            mu = "10.0.0.218";
          }
          // lib.optionalAttrs config.services.prometheus.enable {
            prometheus = ":${toString config.services.prometheus.port}";
          }
          // lib.optionalAttrs config.services.postgres.enable {
            postgres = ":${toString config.services.postgres.port}";
          }
          // lib.optionalAttrs config.services.mailpit.enable {
            mailpit = config.services.mailpit.uiListenAddress;
          }
          // lib.optionalAttrs config.services.sqld.enable {
            sqld = ":${toString config.services.sqld.port}";
          }
          // lib.optionalAttrs config.languages.rust.loco.enable {
            api = "${toString config.languages.rust.loco.config.development.server.binding}:${toString config.languages.rust.loco.config.development.server.port}";
          }
        )
      )
      {
        "tui.localhost".extraConfig = ''
          ${common}
          file_server
          root * ${config.git.root}/tui/dist
        '';
      }
      {
        "web.localhost".extraConfig = ''
          ${common}
          file_server
          root * ${config.git.root}/target/dx/web/release/web/public
        '';
      }
    ];
  };
}
