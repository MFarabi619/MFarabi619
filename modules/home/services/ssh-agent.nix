{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.ssh-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = !config.services.gpg-agent.enable;
    # forwardAgent = false;
    # socket = "ssh-agent"; # default
  };
}
