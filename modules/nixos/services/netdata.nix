{
  pkgs,
  ...
}:
{
  services.netdata = {
   enable = true;
    package = pkgs.netdata.override {withCloudUi = true;};
    # user = "netdata"; # default
    # group = "netadata"; # default
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
    # configText = ''
    #   [global]
    #   debug log = syslog
    #   access log = syslog
    #   error log = syslog
    # '';
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
