{
  pkgs,
  ...
}:
{
  launchd.daemons = {
    # kanata = {
    #   command = "sudo ${pkgs.kanata-with-cmd}/bin/kanata -c /Users/mfarabi/MFarabi619/modules/darwin/kanata.kbd";
    #   serviceConfig = {
    #     KeepAlive = true;
    #     RunAtLoad = true;
    #     StandardOutPath = "/tmp/kanata.out.log";
    #     StandardErrorPath = "/tmp/kanata.err.log";
    #   };
    # };
  };
}
