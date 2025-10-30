{
  # yoinked from: https://www.youtube.com/watch?v=c5Hx4osU5A8
  # nix shell nixpkgs#cloudflared
  # cloudflared tunnel login
  # cloudflared tunnel create cf-demo
  # ls ~/.cloudflared
  # cloudflared tunnel route dns 82210156-ab1e-4171-b117-7936b4b35b57 demo.openws.org
  # sudo mkdir -p /etc/cloudflared
  # sudo chown root:root /etc/cloudflared/
  # sudo chmod 600 /etc/cloudflared/
  # sudo cp ~/.cloudflared/82210156-ab1e-4171-b117-7936b4b35b57.json /etc/cloudflared/

  services.cloudflared = {
    enable = true;
    # certificateFile = /tmp/test;
    tunnels = {
      "dfab631c-28d8-458d-a4ff-ca9b401e9417" = {
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/dfab631c-28d8-458d-a4ff-ca9b401e9417.json";
        # certificateFile = /tmp/test;
        ingress = {
          "api.openws.org" = "http://localhost:80";
          # "api.openws.org" = {
          #   service = "http://localhost:80";
          # };
        };
        # originRequest = {
        #   caPool = "";
        #   proxyPort = 0;
        #   proxyType = "";
        #   tlsTimeout = "10s";
        #   tcpKeepAlive = "30s";
        #   connectTimeout = "30s";
        #   httpHostHeader = "";
        #   noHappyEyeballs = "false";
        #   keepAliveTimeout = "1m30s";
        #   noTLSVerify = false;
        #   proxyAddress = "127.0.0.1";
        #   originServerName = "";
        #   keepAliveConnections = 100;
        #   disableChunkedEncoding = false;
        # };
      };
    };
  };
}
