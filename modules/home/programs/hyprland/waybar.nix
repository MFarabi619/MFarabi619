{
  lib,
  pkgs,
  ...
}:
{
  programs.waybar = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    systemd={
      enable = true;
      # target = config.wayland.systemd.target; # default
      enableDebug = false;
      enableInspect = false;
  };
    settings = {
      mainBar = {
        height = 30;
        mod = "dock";
        layer = "top";
        output = [ "*" ];
        position = "top";
        exclusive = true;
        passthrough = false;
        gtk-layer-shell = true;
        reload_style_on_change = true;

        # modules-left = ["cpu"];
        # modules-center = ["hyprland/workspaces"];
        # modules-right = ["hyprland/workspaces"];

        #       "sway/workspaces" = {
        #         disable-scroll = true;
        #         all-outputs = true;
        #       };
        #       "custom/hello-from-waybar" = {
        #         format = "hello {}";
        #         max-length = 40;
        #         interval = "once";
        #         exec = pkgs.writeShellScript "hello-from-waybar" ''
        #           echo "from within waybar"
        #         '';
        #       };
        #     };
        #   }
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
