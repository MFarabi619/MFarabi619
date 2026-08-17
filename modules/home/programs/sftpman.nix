{
  lib,
  pkgs,
  ...
}:
{
  programs.sftpman = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    # mounts = {
    #   mountOptions = {

    #   };
    # };
  };

}
