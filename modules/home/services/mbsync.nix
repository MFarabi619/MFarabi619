{
  lib,
  pkgs,
  ...
}:
{
  services.mbsync = lib.mkIf pkgs.stdenv.isLinux {
   enable = true;
   verbose = true;
   frequency = "*:0/5";
   # postkexec = "\${pkgs.mu}/bin/mu index";
   # configFile = "~/.mbsyncrc";
   # preExec = "mkdir -p %hmail";
  };
}
