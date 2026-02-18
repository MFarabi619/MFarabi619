{
  config,
  ...
}:
{
  services.prometheus = {
    enable = true;
    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
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
        job_name = "sqld";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.sqld.port}"
            ];
          }
        ];
      }
    ];
  };
}
