{ lib, pkgs, ... }:
{
  imports = [
    ./cachix-agent.nix
    ./gpg-agent.nix
    ./home-manager.nix
    ./skhd.nix
  ];
}
