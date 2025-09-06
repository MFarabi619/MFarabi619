{ lib, pkgs, ... }:
{
  services.skhd = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = ''
      # change window focus within space
      alt - j : yabai -m window --focus south
      alt - k : yabai -m window --focus north
      alt - h : yabai -m window --focus west
      alt - l : yabai -m window --focus east

      cmd - 1 : yabai -m space --focus 1
      cmd - 2 : yabai -m space --focus 2
      cmd - 3 : yabai -m space --focus 3
      cmd - 4 : yabai -m space --focus 4

      # change focus between external displays (left and right)
      alt - s: yabai -m display --focus west
      alt - g: yabai -m display --focus east

      shift + alt - r : yabai -m space --rotate 270 # rotate layout clockwise
      shift + alt - y : yabai -m space --mirror y-axis # flip along y-axis
      shift + alt - x : yabai -m space --mirror x-axis # flip along x-axis

      # toggle window float
      alt + shift - f : yabai -m window --toggle float --grid 4:4:1:1:2:2

      # maximize a window
      alt - return : yabai -m window --toggle zoom-parent

      # balance out tree of windows (resize to occupy same area)
      shift + alt - e : yabai -m space --balance

      # swap windows
      ctrl + shift + alt - j : yabai -m window --swap south
      ctrl + shift + alt - k : yabai -m window --swap north
      ctrl + shift + alt - h : yabai -m window --swap west
      ctrl + shift + alt - l : yabai -m window --swap east

      # move window and split
      ctrl + alt - j : yabai -m window --warp south
      ctrl + alt - k : yabai -m window --warp north
      ctrl + alt - h : yabai -m window --warp west
      ctrl + alt - l : yabai -m window --warp east

      # move window to display left and right
      shift + alt - s : yabai -m window --display west; yabai -m display --focus west;
      shift + alt - g : yabai -m window --display east; yabai -m display --focus east;

      # move window to prev and next space
      shift + alt - h : yabai -m window --space prev
      shift + alt - l : yabai -m window --space next

      # move window to space
      shift + cmd - 1 : yabai -m window --space 1;
      shift + cmd - 2 : yabai -m window --space 2;
      shift + cmd - 3 : yabai -m window --space 3;
      shift + cmd - 4 : yabai -m window --space 4;
      shift + cmd - 5 : yabai -m window --space 5;
      shift + cmd - 6 : yabai -m window --space 6;
      shift + cmd - 7 : yabai -m window --space 7;

      # stop/start/restart yabai
      ctrl + alt - q : yabai --start-service; skhd --start-service
      ctrl + alt - s : yabai --stop-service; skhd --stop-service
      ctrl + alt - r : yabai --restart-service; skhd --reload

      cmd - t : kitty ~
    '';
  };
}
