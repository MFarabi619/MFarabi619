{
  pkgs,
  flake,
  ...
}:
{
  imports = [ flake.inputs.stylix.nixosModules.stylix ];

  stylix = {
    enable = true;
    polarity = "dark";
    homeManagerIntegration.autoImport = false;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    overlays.enable = false;
    fonts.emoji = {
      name = "Twitter Color Emoji";
      package = pkgs.twemoji-color-font;
    };
  };
}
