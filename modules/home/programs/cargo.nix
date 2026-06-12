{
  pkgs,
  ...
}:
{
  programs.cargo.enable = pkgs.stdenv.isLinux;
}
