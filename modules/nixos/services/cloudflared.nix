{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "nixos-server" = {
        default = "http://127.0.0.1:80";
        credentialsFile = "/etc/cloudflared/dc81f04d-07df-4704-abac-07ffabdc173c.json";

        originRequest = {
          tlsTimeout = "10s";
          tcpKeepAlive = "30s";
          connectTimeout = "15s";
          noHappyEyeballs = false;
          keepAliveTimeout = "1m30s";
          keepAliveConnections = 100;
          disableChunkedEncoding = false;
        };
      };
    };
  };
}

# yoinked from: https://www.youtube.com/watch?v=c5Hx4osU5A8
# nix shell nixpkgs#cloudflared
# cloudflared tunnel login
# cloudflared tunnel create nixos-server; ls ~/.cloudflared
# cloudflared tunnel route dns nixos-server api.openws.org
# sudo mkdir -p /etc/cloudflared; sudo chown root:root /etc/cloudflared/; sudo chmod 600 /etc/cloudflared/
# sudo mv ~/.cloudflared/*.json /etc/cloudflared/
# cloudflared tunnel cleanup nixos-server; cloudflared tunnel delete nixos-server
