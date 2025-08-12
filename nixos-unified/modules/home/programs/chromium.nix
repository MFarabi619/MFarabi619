{ pkgs, ... }:
{
  programs.chromium = {
    enable = pkgs.stdenv.isLinux;
    extensions = [
      { id = "dldjpboieedgcmpkchcjcbijingjcgok"; } # fuel wallet
      { id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; } # surfingkeys
    ];
    commandLineArgs = [ ];
    nativeMessagingHosts = [ ];
  };
}
