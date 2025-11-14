{
  pkgs,
  ...
}:
{
  services.netdata = {
    enable = true;

    logDir = "/var/log/netdata"; # default
    workDir = "/var/lib/netdata"; # default
    cacheDir = "/var/cache/netdata"; # default

    package = pkgs.netdata.override {
      withCloudUi = true;
    };

    config = ''
      [global]
      memory mode = ram
      debug log = syslog
      error log = syslog
      access log = syslog
    '';
  };
}
