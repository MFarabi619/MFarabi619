{
  cachix = {
    enable = true;
    pull = [
      "fuellabs"
      "pre-commit-hooks"
      # "rad"
      "oxalica"
      "nixpkgs"
      "nix-community"
      "devenv"
      "nix-darwin"
      "mfarabi"
      "charthouse-labs"
      "cachix"
      "emacs-ci"
    ];
    push = "mfarabi";
  };
}

# nix profile install github:fuellabs/fuel.nix#fuel
# cachix use fuellabs
# fuel-labs:
#   url: github:fuellabs/fuel.nix
#   or
#   url: github:fuellabs/fuel.nix#fuel-nightly
# nix profile list
