{ pkgs, ... }:
{
  services.ttyd = {
    enable = false;
    port = 7681;
    entrypoint = (pkgs.zsh);
    writeable = true;
    terminalType = "xterm-kitty";
    checkOrigin = false;
    logLevel = 7;
    signal = 1;
    maxClients = 0;
    clientOptions = {
      fontSize = "16";
      fontFamily = "Fira Code";
    };
    # indexFile = "";
    # passwordFile = "";
  };
}
