{
  lib,
  pkgs,
  ...
}:
{
  services.netdata = {
    enable = pkgs.stdenv.isLinux;

    package = pkgs.netdata.override {
      withCloudUi = true;
    };
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    logDir = "/var/log/netdata"; # default
    workDir = "/var/lib/netdata"; # default
    cacheDir = "/var/cache/netdata"; # default

    config = ''
      [global]
      memory mode = ram
      debug log = syslog
      access log = syslog
      error log = syslog
    '';
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    deadlineBeforeStopSec = 120;
    enableAnalyticsReporting = false;

    config = {
      global = {
        "memory mode" = "ram";
        "debug log" = "syslog";
        "error log" = "syslog";
        "access log" = "syslog";
      };
    };

    python = {
      enable = true;
      # recommendedPythonPackages = false;
      # extraPackages = ps: with ps; [
      #  psycopg2
      #   docker
      #   dnspython
      # ];
    };

    # configDir = {};
    # claimTokenFile = null;
    # extraPluginPaths = ["/path/to/plugins.d"];
    # extraNdsudoPackages = with pkgs; [
    #   smartmontools
    #   nvme-cli
    # ];
  };
}
