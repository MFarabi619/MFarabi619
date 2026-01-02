{
  pkgs,
  ...
}:
{
  programs.npm = {
    enable = true;
    package = pkgs.nodejs_24;
  };
}
