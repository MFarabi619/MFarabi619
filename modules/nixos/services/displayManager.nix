{
  pkgs,
  ...
}:
{
  services.displayManager = {
    # getty.autologinUser = "mfarabi";
    defaultSession = "hyprland-uwsm";

    sddm = {
      enable = true;
      enableHidpi = true;
      autoNumlock = false;
      # setupScript = "";
      # stopScript = "";
      # extraPackages = [];

      settings = {
        Autologin = {
          User = "mfarabi";
          minimumUid = 1000;
          Session = "hyprland-uwsm";
        };
      };

      wayland = {
        enable = true;
        compositor = "weston";
      };

      theme = "${
        pkgs.where-is-my-sddm-theme.override { variants = [ "qt5" ]; }
      }/share/sddm/themes/where_is_my_sddm_theme_qt5";
    };
  };
}
