{
  config,
  ...
}:
{
  programs.xwayland.enable = config.programs.hyprland.xwayland.enable;
}
