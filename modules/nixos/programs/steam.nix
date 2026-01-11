{
  pkgs,
  ...
}:
{
  programs.steam = {
    enable = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
    extest.enable = true;
  };
}
