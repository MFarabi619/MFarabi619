{
  pkgs,
  ...
}:
{
  packages = with pkgs; [
    presenterm
  ];

  env = {
    PRESENTERM_CONFIG_FILE = "slides/presenterm.config.yaml";
  };
}
