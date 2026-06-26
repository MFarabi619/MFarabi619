{
  pkgs,
  flake,
  ...
}:
{
  imports = [
    flake.inputs.stylix.darwinModules.stylix
  ];

  stylix = {
    enable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    homeManagerIntegration.autoImport = false;
    overlays.enable = false;
    fonts.emoji = {
      name = "Twitter Color Emoji";
      package = pkgs.twemoji-color-font;
    };
  };
}
