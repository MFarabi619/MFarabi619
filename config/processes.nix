{
  lib,
  config,
  ...
}:
{
  processes = {
    api = {
      exec = "cargo loco start --binding 0.0.0.0";
      process-compose = {
        is_tty = true;
        disabled = true;
        namespace = "⚙ Back-End";
        description = "Back-End Server using Loco.rs";
        readiness_probe = {
          http_get = {
            port = "5150";
            scheme = "http";
            host = "localhost";
          };
        };
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
        # caddy.disabled = true;
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
