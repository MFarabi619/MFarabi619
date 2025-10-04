{
  programs.waybar = {
    enable = true;
    systemd={
      enable = true;
      # target = config.wayland.systemd.target; # default
      enableDebug = false;
      enableInspect = false;
  };
    settings = {
      mainBar = {
        layer = "top";
        output = [ "*" ];
        position = "top";
        mod = "dock";
        height = 31;
        exclusive = true;
        passthrough = false;
        gtk-layer-shell = true;
        reload_style_on_change = true;
        # modules-left = ["cpu"];
        # modules-center = ["hyprland/workspaces"];
        # modules-right = ["hyprland/workspaces"];
      };
    };
  # style = ''
  #   * {
  #   border: none;
  #   border-radius: 0;
  #   font-family: Jetbrains Mono;
  #   }
  # '';
};
  }
