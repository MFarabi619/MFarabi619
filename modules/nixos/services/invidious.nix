{
  config,
  ...
}:
{
  services.invidious = {
    port = 3900;
    # sig-helper.enable = true;
    # settings.autoplay = true;
    # http3-ytproxy.enable = true;
    # settings.player_style = "invidious";
    enable = config.networking.hostName == "framework-desktop";
  };
}
