{
  lib,
  pkgs,
  ...
}:
{
  services.jellyfin-mpv-shim = lib.mkIf pkgs.stdenv.isLinux {
    enable = false;
    settings = {
      auto_play = true;
      fullscreen = true;
    };
    # mpvConfig = {};
    mpvBindings = {
      WHEEL_UP = "seek 10";
      WHEEL_DOWN = "seek -10";
    };
  };
}
