{
  pkgs,
  config,
  ...
}:
{
  programs.anki = {
    enable = true;
    uiScale = 1.0;
    hideTopBar = true;
    reduceMotion = true;
    hideBottomBar = true;
    minimalistMode = true;
    # spacebarRatesCard = true;
    hideTopBarMode = "fullscreen"; # fullscreen | always
    hideBottomBarMode = "fullscreen"; # fullscreen | always
    # videoDriver = "opengl"; # andle | software | metal | vulkan | d3d11
    # answerKeys = {};

    addons = with pkgs.ankiAddons; [
      anki-connect
      review-heatmap
    ];

    sync = {
      # keyFile = "";
      autoSync = true;
      syncMedia = true;
      # usernameFile = "";
      networkTimeout = 60;
      autoSyncMediaMinutes = 15;
      username = config.me.email;
      url = "https://anki.microvisor.dev";
    };
  };
}
