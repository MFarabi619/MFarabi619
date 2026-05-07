{
  pkgs,
  config,
  ...
}:
{
  programs.aria2p.enable = config.programs.aria2.enable && pkgs.stdenv.isLinux;
}
