{
  lib,
  pkgs,
  ...
}:
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf pkgs.stdenv.isDarwin pkgs.ghostty-bin;
    settings = {
      macos-icon = "microchip";
      macos-option-as-alt = true;
      macos-window-buttons = "hidden";
      macos-titlebar-style = "hidden";
    };
  };
}
