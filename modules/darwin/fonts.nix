{
pkgs,
...
}:
{
  fonts.packages = with pkgs; [
   nerd-fonts.noto
   nerd-fonts.jetbrains-mono
   sketchybar-app-font
  ];
}
