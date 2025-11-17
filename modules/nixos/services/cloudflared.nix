{
  # yoinked from: https://www.youtube.com/watch?v=c5Hx4osU5A8
  # nix shell nixpkgs#cloudflared
  # cloudflared tunnel login
  # cloudflared tunnel create nixos-server
  # ls ~/.cloudflared
  # cloudflared tunnel route dns nixos-server api.openws.org
  # sudo mkdir -p /etc/cloudflared
  # sudo chown root:root /etc/cloudflared/
  # sudo chmod 600 /etc/cloudflared/
  # sudo mv ~/.cloudflared/82210156-ab1e-4171-b117-7936b4b35b57.json /etc/cloudflared/
  # cloudflared tunnel cleanup nixos-server; cloudflared tunnel delete nixos-server

  services.cloudflared = {
    enable = true;
    # certificateFile = "/etc/cloudflared/tunnel.cert.pem";

    tunnels = {
      "nixos-server" = {
        default = "http://127.0.0.1:80";
        # certificateFile = /tmp/test;
        credentialsFile = "/etc/cloudflared/dc81f04d-07df-4704-abac-07ffabdc173c.json";

        originRequest = {
          # caPool = "";
          # proxyPort = 0;
          # proxyType = "";
          tlsTimeout = "10s";
          # noTLSVerify = false;
          tcpKeepAlive = "30s";
          connectTimeout = "15s";
          # httpHostHeader = "";
          noHappyEyeballs = false;
          keepAliveTimeout = "1m30s";
          # proxyAddress = "127.0.0.1";
          keepAliveConnections = 100;
          disableChunkedEncoding = false;
          # originServerName = "";
        };
      };
    };
  };
}
