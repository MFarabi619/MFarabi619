{
  lib,
  pkgs,
  ...
}:
{
  programs.rofi = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      package = pkgs.rofi;
      location = "center";
      # font = "JetBrainsMono Nerd Font Mono 12";
      extraConfig = {
        show-icons = true;
        # icon-theme = "Papirus";
        display-run = "Run";
        display-drum = "Apps";
        display-filebrowser = "File";
        drun-display-format = "{icon} {name}";
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
}
