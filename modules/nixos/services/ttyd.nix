{ pkgs, ... }:
{
  services.ttyd = {
    enable = false;
    port = 7681;
    signal = 1;
    logLevel = 7;
    maxClients = 0;
    writeable = true;
    checkOrigin = false;
    entrypoint = (pkgs.zsh);
    terminalType = "xterm-kitty";
    clientOptions = {
      fontSize = "16";
      fontFamily = "Fira Code";
    };
    # indexFile = "";
    # passwordFile = "";
  };
}
