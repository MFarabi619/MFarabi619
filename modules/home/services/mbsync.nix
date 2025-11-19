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
   preExec = "${pkgs.isync}/bin/mbsync -Ha";
   postExec = "${pkgs.mu}/bin/mu index -m /home/mfarabi/Maildir";
  };
}
