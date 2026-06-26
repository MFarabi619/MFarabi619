{
  imports = [
    ./ipfs.nix
    ./aerospace.nix
    ./karabiner-elements.nix

    ../../nixos/services/netbird.nix
    ../../nixos/services/netdata.nix
    ../../nixos/services/openssh.nix
    ../../nixos/services/tailscale.nix
    ../../nixos/services/github-runners.nix
  ];
}
