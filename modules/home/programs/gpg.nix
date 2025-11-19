{
  programs.gpg = {
    enable = true;
    mutableKeys = true;
    mutableTrust = true;
    # settings = {};
    # scdaemonSettings = { };

    publicKeys = [
      {
        source = ../gpg-public.asc;
        trust = "ultimate";
      }
    ];
  };
}
