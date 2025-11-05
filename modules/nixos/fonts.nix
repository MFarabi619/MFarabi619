{ pkgs, lib, ... }:
{
  fonts.packages =
      with pkgs;
      [
        symbola
        fira-code
        font-awesome
        material-icons
        fira-code-symbols
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        nerd-fonts.jetbrains-mono
      ]
      ++ lib.optionals stdenv.isDarwin [
        sketchybar-app-font
      ];
}
