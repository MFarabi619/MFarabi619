{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.ttyd = {
    # enable = config.networking.hostName == "framework-desktop"; # BUG: broken as of Jun 13, 2026
    enable = false;
    logLevel = 7;
    maxClients = 0;
    # indexFile = "";
    # enableSSL = true;
    # user = "root"; # NOTE necessary for login!
    writeable = false;
    # username = "";
    # passwordFile = pkgs.writeText "ttydpw" "";
    checkOrigin = false;
    # interface = "wlp192s0";
    # terminalType = "xterm-kitty";

    entrypoint = [
      # "${pkgs.shadow}/bin/login"
      # (lib.getExe pkgs.fastfetch)
      (lib.getExe pkgs.asciiquarium)
    ];

    clientOptions = {
      fontSize = "16";
      enableSixel = "true";
      enableTrzsz = "true";
      enableZmodem = "true";
      fontFamily = "JetBrainsMono Nerd Font";
    };
  };
}
