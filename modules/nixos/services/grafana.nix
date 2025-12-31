{
  config,
  ...
}:
let
  ROOT_DOMAIN = "openws.org";
in
{
  services.grafana = {
    enable = true;
    settings = {
      server = {
        enable_gzip = true;
        domain = ROOT_DOMAIN;
        serve_from_sub_path = true;
        root_url = "https://${ROOT_DOMAIN}/grafana/"; # Not needed if it is `https://your.domain/`
      };

      users = {
        # allow_sign_up = false;
        password_hint = "password";
        verify_email_enabled = true;
        login_hint = "email address";
      };

      auth = {
        # disable_login_form = true;
        "auth.google" = [
          "enabled = true"
          "allow_sign_up = true"
          "client_id = "
        ];
      };

      analytics = {
        check_for_updates = false;
        reporting_enabled = false;
        feedback_links_enabled = false;
        # check_for_plugin_updates = true;
      };

      security = {
        disable_initial_admin_creation = false;
        disable_brute_force_login_protection = false;
      };
    };

    provision = {
      enable = true;

      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "prometheus";
            type = "prometheus";
            url = "http://localhost:${toString config.services.prometheus.port}";
          }
        ];
      };

      # dashboards.settings.providers = [{
      #   name = "my dashboards";
      #   disableDeletion = true;

      #   options = {
      #     path = "/etc/grafana-dashboards";
      #     foldersFromFilesStructure = true;
      #     };
      #   }];
    };

  };
}
