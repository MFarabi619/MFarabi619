{
  pkgs,
  ...
}:
{
  programs.obs-studio = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    plugins = [ ];
  };
}
