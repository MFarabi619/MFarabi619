{ pkgs, ... }:
{
  programs.obs-studio = {
    enable = pkgs.stdenv.isLinux;
    plugins = [ ];
  };
}
