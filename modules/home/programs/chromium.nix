{
  pkgs,
  ...
}:
{
  programs.chromium = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    commandLineArgs = [ ];
    nativeMessagingHosts = [ ];

    extensions = [
      { id = "dldjpboieedgcmpkchcjcbijingjcgok"; } # fuel wallet
      { id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; } # surfingkeys
    ];
  };
}
