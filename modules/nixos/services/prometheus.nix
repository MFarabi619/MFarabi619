{
  config,
  ...
}:
{
  services.prometheus = {
    enable = true;
     scrapeConfigs = [
      {
        job_name = "esp32";
        scrape_interval = "5s";
        static_configs = [{
          targets = [
            config.services.grafana.settings.server.domain
          ];
        }];
      }
    ];
  };
}
