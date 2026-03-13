{
  lib,
  config,
  ...
}:
{
  processes = {
    "cargo:loco:watch" = {
      exec = "cargo loco watch";
      ports.http.allocate = config.languages.rust.loco.config.development.server.port;
      process-compose = {
        is_tty = true;
        namespace = "🧩 API";
      };
    };
  }
  //
    builtins.mapAttrs
      (_: cfg: {
        process-compose = {
          is_tty = true;
          namespace = "🎡 SERVICES";
        };
      })
      {

        sqld.enable = false;
        caddy.enable = true;
        mailpit.enable = true;
        prometheus.enable = false;
        "tailscale-funnel".enable = false;
      }
  // lib.optionalAttrs (!config.devenv.isTesting) {
    console = {
      exec = ''
        ttyd --writable --browser --url-arg --once devenv up
      '';
      process-compose = {
        disabled = true;
        namespace = "🧮 VIEWS";
        description = "🕹 Attach the Microvisor Kernel to the Browser";
      };
    };
  };

  process = {
    manager.args = {
      "config" = "${config.git.root}/config/process-compose/settings.yaml";
      "shortcuts" = "${config.git.root}/config/process-compose/shortcuts.yaml";
    };

    managers.process-compose.settings = {
      is_strict = true;
      #   availability = {
      #   max_restarts = 5;
      #   backoff_seconds = 2;
      #   restart = "on_failure";
      # };
    };
  };
}
