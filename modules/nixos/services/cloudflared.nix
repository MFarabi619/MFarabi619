{
  services.cloudflared = {
    enable = false;
    # certificateFile = /tmp/test;
    # tunnels = {
    #   "0000" = {
    #     default = "http_status:404";
    #     certificateFile = /tmp/test;
    #     credentialsFile = "/tmp/test";
    #     ingress = {
    #       "*.mfarabi.sh" = {
    #         service = "http://localhost:80";
    #       };
    #     };
    #     originRequest = {
    #       caPool = "";
    #       proxyPort = 0;
    #       proxyType = "";
    #       tlsTimeout = "10s";
    #       tcpKeepAlive = "30s";
    #       connectTimeout = "30s";
    #       httpHostHeader = "";
    #       noHappyEyeballs = "false";
    #       keepAliveTimeout = "1m30s";
    #       noTLSVerify = false;
    #       proxyAddress = "127.0.0.1";
    #       originServerName = "";
    #       keepAliveConnections = 100;
    #       disableChunkedEncoding = false;
    #     };
    #   };
    # };
  };
}
