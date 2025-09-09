{ pkgs, lib, ... }:
{
  fonts.packages =
      with pkgs;
      [
        symbola
        fira-code
        font-awesome
        material-icons
        noto-fonts-emoji
        fira-code-symbols
        noto-fonts-cjk-sans
        nerd-fonts.jetbrains-mono
      ]
      ++ lib.optionals stdenv.isDarwin [
        sketchybar-app-font
      ];
}
