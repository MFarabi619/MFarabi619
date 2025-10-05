{
  services.netdata = {
    enable = true;
    config = "";
    logDir = "/var/log/netdata"; # default
    workDir = "/var/lib/netdata"; # default
    cacheDir = "/var/cache/netdata"; # default
  };
}
