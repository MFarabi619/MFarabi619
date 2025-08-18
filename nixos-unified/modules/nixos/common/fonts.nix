{ pkgs, lib, ... }:
{
  fonts = {
    packages =
      with pkgs;
      [
        noto-fonts-emoji
        noto-fonts-cjk-sans
        font-awesome
        symbola
        material-icons
        fira-code
        fira-code-symbols
        nerd-fonts.jetbrains-mono
      ]
      ++ lib.optionals stdenv.isDarwin [
        sketchybar-app-font
      ];
  };
}
