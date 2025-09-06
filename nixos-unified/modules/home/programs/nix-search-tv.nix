{
  programs.nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;
    settings = {
      indexes = [
        "nur"
        "nixos"
        "darwin"
        "nixpkgs"
        "home-manager"
        # "nixos-wsl"
        # "nix-on-droid"
        # "nixos-raspberry-pi"
      ];
    };
  };
}
