{
pkgs,
...
}:
{
  fonts.packages = with pkgs; [
   nerd-fonts.noto
   sketchybar-app-font
   nerd-fonts.jetbrains-mono
  ];
}
