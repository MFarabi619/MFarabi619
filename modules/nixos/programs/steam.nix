{
  pkgs,
  ...
}:
{
  programs.steam = {
    enable = pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.isx86_64;
    extest.enable = true;
  };
}
