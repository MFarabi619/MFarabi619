# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
  ];
  services.openssh.enable = true;
}}

#   {
#   description = "Mumtahin Farabi's NixOS Configuration.";

#   inputs = {
#     nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

#     hydenix = {
#       # Hydenix and its nixpkgs - kept separate to avoid conflicts
#       url = "github:richen604/hydenix"; # Main
#       # Available inputs:
#       # url = "github:richen604/hydenix/dev"; # Dev
#       # url = "github:richen604/hydenix/<commit-hash>"; # Commit
#       # url = "github:richen604/hydenix/v1.0.0"; # Version
#     };

#     nix-index-database = {
#       # Nix-index-database - for comma and command-not-found
#       url = "github:nix-community/nix-index-database";
#       inputs.nixpkgs.follows = "nixpkgs";
#     };

#     nix-doom-emacs-unstraightened = {
#       url = "github:marienz/nix-doom-emacs-unstraightened";
#       inputs.nixpkgs.follows = "";
#     };

#     playwright-web-flake.url = "github:pietdevries94/playwright-web-flake";
#   };

#   outputs =
#     { ... }@inputs:

#     let
#       HOSTNAME = "hydenix";

#       hydenixConfig = inputs.hydenix.inputs.hydenix-nixpkgs.lib.nixosSystem {
#         inherit (inputs.hydenix.lib) system;
#         specialArgs = {
#           inherit inputs;
#         };
#         modules = [
#           ./configuration.nix
#         ];
#       };
#     in
#     {
#       nixosConfigurations = {
#         nixos = hydenixConfig;
#         ${HOSTNAME} = hydenixConfig;
#       };
#     };
# }
