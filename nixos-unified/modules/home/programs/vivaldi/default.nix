{ pkgs, ... }:
{
  programs.vivaldi.enable = pkgs.stdenv.isLinux;
}
