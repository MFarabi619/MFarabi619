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
          disabled = cfg.disabled or false;
        };
      })
      {
        sqld.disabled = true;
        caddy.disabled = false;
        mailpit.disabled = false;
        prometheus.disabled = true;
        "tailscale-funnel".disabled = true;
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
