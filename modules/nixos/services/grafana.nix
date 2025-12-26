let
  # ROOT_DOMAIN = "openws.org";
  ROOT_DOMAIN = "iot.apidaesystems.ca";
in
  {
  services.grafana =  {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        enable_gzip = true;
        domain = ROOT_DOMAIN;
        http_addr = "127.0.0.1";
        serve_from_sub_path = true;
        root_url = "https://${ROOT_DOMAIN}/grafana/"; # Not needed if it is `https://your.domain/`
      };

      users = {
        # allow_sign_up = false;
        default_theme = "dark";
        password_hint = "password";
        verify_email_enabled = true;
        login_hint = "email address";
      };

      auth =  {
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

      # provision =  {
      #   enable = true;

      #   dashboards.settings.providers = [{
      #     name = "my dashboards";
      #     disableDeletion = true;

      #     options = {
      #       path = "/etc/grafana-dashboards";
      #       foldersFromFilesStructure = true;
      #       };
      #     }];
      # };

      security = {
        disable_initial_admin_creation = false;
        disable_brute_force_login_protection = false;
      };
    };
  };
}
