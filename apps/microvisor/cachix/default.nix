{
  cachix = {
    enable = true;
    push = "mfarabi";
    pull = [
      "cachix"
      "oxalica"
      "devenv"
      "nixpkgs"
      "mfarabi"
      "emacs-ci"
      "nix-darwin"
      "nix-community"
      "pre-commit-hooks"
    ];
  };
}

# nix profile install github:fuellabs/fuel.nix#fuel
# cachix use fuellabs
# fuel-labs:
#   url: github:fuellabs/fuel.nix
#   or
#   url: github:fuellabs/fuel.nix#fuel-nightly
# nix profile list
