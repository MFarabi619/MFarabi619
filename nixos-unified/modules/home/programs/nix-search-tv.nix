{
  programs.nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;
    settings = {
      indexes = [
        "nixpkgs"
        "home-manager"
        "nixos"
        "nix-darwin"
      ];
    };
  };
}
