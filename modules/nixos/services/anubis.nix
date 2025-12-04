{
  services.anubis = {
    defaultOptions = {
      settings = {
        DIFFICULTY = 4;
        BIND_NETWORK = "tcp";
        METRICS_BIND_NETWORK = "tcp";
      };
    };

    instances = {
      # ai = {
      #   settings = {
      #     BIND = ":7776";
      #     TARGET = "http://127.0.0.1:7777";
      #     METRICS_BIND = "127.0.0.1:7778";
      #   };
      # };

      # nixos = {
      #   settings = {
      #     BIND = ":7680";
      #     TARGET = "http://127.0.0.1:7681";
      #     METRICS_BIND = "127.0.0.1:7682";
      #   };
      # };

      index = {
        settings = {
          BIND = ":8087";
          TARGET = "http://127.0.0.1:8088";
          METRICS_BIND = "127.0.0.1:8089";
        };
      };


      mirror = {
        settings = {
          BIND = ":11000";
          TARGET = "http://192.168.50.142";
          METRICS_BIND = "127.0.0.1:11001";
        };
      };

      # iot = {
      #   settings = {
      #     BIND = ":8079";
      #     TARGET = "http://127.0.0.1:8080";
      #     METRICS_BIND = "127.0.0.1:8081";
      #   };
      # };

      tandemrobotics = {
        settings = {
          BIND = ":5149";
          TARGET = "http://192.168.50.142:5150";
          METRICS_BIND = "127.0.0.1:5151";
        };
      };
    };
  };
}
