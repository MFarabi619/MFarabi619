{
  lib,
  pkgs,
  ...
}:
{
  programs.sftpman = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    # mounts = {
    #   mountOptions = {

    #   };
    # };
  };

}
