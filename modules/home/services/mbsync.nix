{
  lib,
  pkgs,
  ...
}:
{
  services.mbsync = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    verbose = true;
    frequency = "*:0/15";
    postExec = "${pkgs.mu}/bin/mu index";
    preExec = "${pkgs.isync}/bin/mbsync -VXa";
  };
}
