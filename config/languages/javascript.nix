{
  config,
  pkgs,
  ...
}:
{
  languages.javascript = {
    bun.enable = true;
    package = pkgs.nodejs_26;
    enable = config.languages.typescript.enable;
  };
}
