{
  services.radicle = {
    enable = false;
    checkConfig = true;
    privateKeyFile = "/run/secrets/radicle/seednode";

    httpd = {
      enable = true;
      nginx = {
        enableACME = true;
        forceSSL = true;
        serverName = "radicle.dpc.pw";
      };
    };

    node = {
      listenPort = 8776;
      listenAddress = "127.0.0.1";
    };

    ci = {
      broker = {
        enable = false;
      };
    };

    # publicKey = ../../../configurations/home/id_ed25519.pub;
    # settings = {
    #   web.pinned.repositories = [
    #    "rad:..."
    #   ];
    # };
  };
}
