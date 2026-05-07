{
  lib,
  pkgs,
  ...
}:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    enableExtraSocket = true;
    enableBrowserSocket = true;
  };
}
