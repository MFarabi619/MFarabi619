{lib, pkgs, ...}:
{
  programs = lib.mkIf pkgs.stdenv.isLinux {
    waybar = {
      enable = true;
      # package = pkgs.waybar;

      systemd = {
       enable = true;
       # target = "";
       # enableInspect = true;
       # enableDebug = true;
      };

      # settings = [
      #   {
      #     mainBar = {
      #       layer = "top";
      #       position = "top";
      #       height = 30;
      #       output = [
      #         "eDP-1"
      #         "HDMI-A-1"
      #       ];
      #       modules-left = [ "sway/workspaces" "sway/mode" "wlr/taskbar" ];
      #       modules-center = [ "sway/window" "custom/hello-from-waybar" ];
      #       modules-right = [ "mpd" "custom/mymodule#with-css-id" "temperature" ];

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
      # ];
    };

    rofi = {
      enable = true;
      package = pkgs.rofi-wayland;
      location = "center";
      # font = "JetBrainsMono Nerd Font Mono 12";
      extraConfig = {
        show-icons = true;
        # icon-theme = "Papirus";
        drun-display-format = "{icon} {name}";
        display-drum = "Apps";
        display-run = "Run";
        display-filebrowser = "File";
      };
      # terminal = "${pkgs.kitty}/";
      # plugins = with pkgs; [ ];
      modes = [
        "drun"
        # "emoji"
        "ssh"
      ];
      # pass = {
      #   enable = true;
      #   };
    };
  };
}
