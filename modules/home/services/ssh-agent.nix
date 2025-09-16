{
  lib,
  pkgs,
  ...
}:
{
  services.ssh-agent = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    # forwardAgent = false;
    # socket = "ssh-agent"; # default
  };
}
