{
  services.jellyfin-mpv-shim = {
   enable = true;
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
