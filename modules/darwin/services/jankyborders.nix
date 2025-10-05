{
  lib,
  pkgs,
  ...
}:
{
  services.jankyborders = {
    width = 6.0;
    hidpi = true;
    enable = true;
    order = "below";
    style = "round";
    ax_focus = false; # use slower accessibility focus api if true
    blur_radius = 6.0;
    # active_color = "";
    # inactive_color = "";
    # blacklist = [
    #   "kitty"
    #   "emacs"
    # ];

    # whitelist = [
    #   "kitty"
    #   "emacs"
    # ];
  };
}
