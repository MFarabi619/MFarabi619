{
  config,
  ...
}:
{
  programs.uwsm = {
    enable = config.programs.hyprland.withUWSM;
    # waylandCompositors = {
    #     prettyName = "Hyprland";
    #     comment = "Hyprland compositor managed by UWSM";
    #     binPath = "/run/current-system/sw/bin/hyprland";
    # };
  };
}
