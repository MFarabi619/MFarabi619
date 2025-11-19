{
  pkgs,
  ...
}:
{
  programs.chromium = {
    enable = pkgs.stdenv.isLinux;
    commandLineArgs = [ ];
    nativeMessagingHosts = [ ];

    extensions = [
      { id = "dldjpboieedgcmpkchcjcbijingjcgok"; } # fuel wallet
      { id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; } # surfingkeys
    ];
  };
}
