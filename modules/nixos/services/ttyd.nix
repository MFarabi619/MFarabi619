{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.ttyd = {
    enable = config.networking.hostName == "framework-desktop";
    logLevel = 7;
    maxClients = 0;
    # indexFile = "";
    # enableSSL = true;
    # user = "root"; # NOTE necessary for login!
    writeable = false;
    # username = "";
    # passwordFile = pkgs.writeText "ttydpw" "";
    checkOrigin = false;
    interface = "127.0.0.1";
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
