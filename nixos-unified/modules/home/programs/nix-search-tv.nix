{
  programs.nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;
    settings = {
      indexes = [
        "nur"
        "nixos"
        "nixpkgs"
        "darwin"
        "home-manager"
        # "nixos-wsl"
        # "nix-on-droid"
        # "nixos-raspberry-pi"
      ];
    };
  };
}
