{
  inputs,
  config,
  pkgs,
  ...
}:

{

  imports = [
    inputs.lazyvim.homeManagerModules.default
    inputs.nix-doom-emacs-unstraightened.homeModule
  ];

  home = {
    username = "mfarabi";
    homeDirectory = "/home/mfarabi";
    stateVersion = "25.05";
  };
}
