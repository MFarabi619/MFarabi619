{
  config,
  ...
}:
{
  services.prometheus = {
    enable = config.services.grafana.enable;

    globalConfig = {
      scrape_interval = "5s";
      scrape_timeout = "5s";
    };

    exporters = {
      node = {
        enable = true;
        # enabledCollectors = [
        #   "systemd"
        #   "cpu_vulnerabilities"
        # ];
      };
      # process.enable = true;
      # systemd.enable = true;
      # smartctl.enable = true;
      # tailscale.enable = true;
    };

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.port}"
            ];
          }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.node.port}"
            ];
          }
        ];
      }
      # {
      #   job_name = "esp32";
      #   scrape_interval = "5s";
      #   static_configs = [
      #     {
      #       targets = [
      #         "192.168.50.16"
      #       ];
      #     }
      #   ];
      # }
    ];
  };
}
