{
  programs.chromium = {
    enable = true;
    extensions = [
      { id = "dldjpboieedgcmpkchcjcbijingjcgok"; } # fuel wallet
      { id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; } # surfingkeys
    ];
    commandLineArgs = [ ];
    nativeMessagingHosts = [ ];
  };
}
