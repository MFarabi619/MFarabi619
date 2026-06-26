{
  pkgs,
  flake,
  ...
}:
{
  imports = [
    flake.inputs.stylix.nixosModules.stylix
  ];

  stylix = {
    enable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    homeManagerIntegration.autoImport = false;
  };
}
