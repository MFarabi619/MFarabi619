{
  networking = rec {
    hostName = "macos";
    computerName = hostName;
    localHostName = hostName;
    wakeOnLan.enable = true;
  };
}
