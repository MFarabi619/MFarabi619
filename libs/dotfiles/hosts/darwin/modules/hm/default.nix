{ config, lib, pkgs, ... }:

{
  home = {
  stateVersion = "25.05";
  username = "mfarabi";
  };

  programs = {
  home-manager.enable = true;
  lazygit = {
    enable = true;
  };
  };
}
