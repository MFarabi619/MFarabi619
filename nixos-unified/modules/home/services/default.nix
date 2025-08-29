{ lib, pkgs, ... }:
{
  imports = [
    ./cachix-agent.nix
    ./gpg-agent.nix
    ./home-manager.nix
    ./ssh-agent.nix
    ./skhd.nix
    ./ollama.nix
    ./glance.nix
  ];
}
