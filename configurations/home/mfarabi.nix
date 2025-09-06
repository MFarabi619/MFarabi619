{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.homeModules.default
  ];

  # Defined by /modules/home/me.nix
  # And used all around in /modules/home/*
  me = {
    username = "mfarabi";
    fullname = "Mumtahin Farabi";
    email = "mfarabi619@gmail.com";
  };

  home.stateVersion = "25.05";
}
