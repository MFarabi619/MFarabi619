{
  lib,
  config,
  ...
}:
{
  services.anubis = lib.mkIf (config.networking.hostName == "framework-desktop") {
    defaultOptions = {
      settings = {
        DIFFICULTY = 4;
        BIND_NETWORK = "tcp";
        METRICS_BIND_NETWORK = "tcp";
      };
    };

    instances = {
      homepage-dashboard = {
        settings = {
          BIND = ":${toString (config.services.homepage-dashboard.listenPort - 1)}";
          TARGET = "http://127.0.0.1:${toString config.services.homepage-dashboard.listenPort}";
          METRICS_BIND = "127.0.0.1:${toString (config.services.homepage-dashboard.listenPort + 1)}";
        };
      };

      mirror = {
        settings = {
          BIND = ":11000";
          TARGET = "http://10.0.0.142";
          METRICS_BIND = "127.0.0.1:11001";
        };
      };

      tandemrobotics = {
        settings = {
          BIND = ":5149";
          TARGET = "http://10.0.0.122:80";
          METRICS_BIND = "127.0.0.1:5151";
        };
      };
    };
  };
}
