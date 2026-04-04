{
  config,
  ...
}:
{
  languages.rust = {
    enable = true;
    channel = "stable";
    # lld.enable = true;  # FIXME: breaks dioxus
    # mold.enable = true; # FIXME: breaks loco

    components = [
      "rustc"
      "cargo"
      "clippy"
      "rustfmt"
      "rust-std"
      "rust-src"
      "rust-analyzer"
    ];

    loco = {
      enable = true;
      config = rec {
      writeConfig = false;
        development = {
          mailer.smtp.host = "mailpit.localhost";
          database.uri = "sqlite://microvisor_development.sqlite?mode=rwc";

          logger = {
            level = "info";
            format = "pretty";
          };

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
      application = {
        # base_path = "web";
        # asset_dir = "assets";
        tailwind_input = "tailwind.css";
        tailwind_output = "assets/tailwind.css";
      };

      web = {
        # pre_compress = true;
        # proxy.backend = "http://localhost:8000/api/"
        app = {
          title = "🕹 Microvisor Systems 🕹";
        };

        # watcher.watch_path = ["web" "web/src" "web/assets"];
        # resource = {
        #   script = [ "https://docs.openws.org/likec4-views.js" ];
        #   # style = ["https://cdn.jsdelivr.net/gh/devicons/devicon@latest/devicon.min.css"]
        #   dev = {
        #     # Javascript code file
        #     # serve: [dev-server] only
        #     script = [ ];
        #   };
        # };

        # https= {
        # # enabled = true
        # # mkcert = true
        # # key_path = "/path/to/key"
        # # cert_path = "/path/to/cert"
        # };
      };

      bundle = {
        category = "Utility";
        publisher = "Mumtahin Farabi";
        icon = [ "assets/symbolmark.png" ];
        identifier = "com.microvisorsystems";
        copyright = "2026 Microvisor Systems";
        short_description = "General web client.";
      };
    };
  };
}
