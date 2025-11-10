{
  pkgs,
  lib,
  ...
}:
{
  services.ttyd = {
    enable = true;
    signal = 1;
    port = 7681;
    logLevel = 7;
    maxClients = 0;
    # indexFile = "";
    # enableSSL = true;
    # user = "root"; # NOTE necessary for login!
    writeable = true;
    # username = "";
    # passwordFile = pkgs.writeText "ttydpw" "";
    checkOrigin = false;
    interface = "0.0.0.0";
    entrypoint = [
      "${pkgs.shadow}/bin/login"
      # (lib.getExe pkgs.btop)
    ];
    # terminalType = "xterm-kitty";
    clientOptions = {
      fontSize = "16";
      enableSixel = "true";
      enableTrzsz = "true";
      enableZmodem = "true";
      fontFamily = "JetBrainsMono Nerd Font";
    };
  };
}
