{
  programs.gpg = {
    enable = true;
    # homedir = "${config.home.homeDirectory}/.gnupg"; # default
    # settings = {};
    # scdaemonSettings = { };
    mutableKeys = true; # default
    mutableTrust = true; # default
    publicKeys = [
      # { source = ./pubkeys.txt; }
    ];
  };
}
