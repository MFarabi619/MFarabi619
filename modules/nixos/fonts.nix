{
  pkgs,
  lib,
  ...
}:
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
      twemoji-color-font
      nerd-fonts.jetbrains-mono
    ]
    ++ lib.optionals stdenv.isDarwin [
      nerd-fonts.noto
      sketchybar-app-font
    ];
}
