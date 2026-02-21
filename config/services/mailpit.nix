{
  pkgs,
  ...
}:
{
  services.mailpit.enable = !(pkgs.stdenv.isLinux && pkgs.stdenv.isAarch64);
}
