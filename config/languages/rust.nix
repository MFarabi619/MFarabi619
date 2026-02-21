{
  config,
  ...
}:
{
  languages.rust = {
    enable = true;
    channel = "stable";
    embassy.enable = true;

    loco = {
      enable = true;
      config = {
        development = {
          logger.format = "pretty";
          mailer.smtp.host = "mailpit.localhost";
          database.uri = "sqlite://api_development.sqlite?mode=rwc";
          server.middlewares = {
            fallback.enable = false;
            static = {
              fallback = "${config.git.root}/assets/static/404.html";
              folder = {
                uri = "/";
                path = "${config.git.root}/assets/static";
              };
            };
          };
        };

        extra_config.initializers.openapi.redoc = {
          url = "/redoc";
          spec_json_url = "/api-docs/openapi.json";
          spec_yaml_url = "/api-docs/openapi.yaml";
        };
      };
    };

    dioxus = {
      enable = true;
      desktop.linux.enable = false;
      mobile.android.enable = false;
    };

    components = [
      "rustc"
      "cargo"
      "clippy"
      "rustfmt"
      "rust-analyzer"
    ];
  };
}
