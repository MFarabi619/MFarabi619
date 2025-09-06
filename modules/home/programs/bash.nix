{ pkgs, lib, ... }:
{
  programs.bash = {
    enable = true;
    initExtra = ''
      # Custom bash profile goes here
    '';
  };
}
