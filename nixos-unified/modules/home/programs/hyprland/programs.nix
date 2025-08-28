{lib, pkgs, ...}:
{
  programs = lib.mkIf pkgs.stdenv.isLinux {
    waybar = {
      enable = true;
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
      # plugins = with pkgs; [
      # ];
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
