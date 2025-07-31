{ flake, pkgs, ... }:
{
  imports = [
    ./programs
  ];
  # Nix packages to install to $HOME
  # search.nixos.org/packages
  home.packages = with pkgs; [
    omnix

    # Unix tools
    # ripgrep # Better `grep`
    fd
    sd
    tree
    gnumake

    # Nix dev
    cachix
    nil # Nix language server
    nix-info
    nixpkgs-fmt

    # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
    # work.
    less

    # Setup Claude Code using Google Vertex AI Platform
    # https://github.com/juspay/vertex
    flake.inputs.vertex.packages.${system}.default
  ];

  # Programs natively supported by home-manager.
  # They can be configured in `programs.*` instead of using home.packages.
  programs = {
    tmate = {
      enable = true;
      #host = ""; #In case you wish to use a server other than tmate.io 
    };
  };
}
