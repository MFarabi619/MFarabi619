{
  pkgs,
  ...
}:
{
  programs.cargo.enable = pkgs.stdenv.hostPlatform.isLinux;
}
