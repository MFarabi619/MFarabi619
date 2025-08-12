{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home.stateVersion = "24.05";
  imports = [
    ../../modules/home/programs
    ../../modules/home/manual.nix
  ];
}
