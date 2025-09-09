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
      experimental = {
       render_docs_indexes = {
        nix-on-droid = "https://nix-community.github.io/nix-on-droid/nix-on-droid-options.html";
        nixos-wsl = "https://nix-community.github.io/NixOS-WSL/options.html";
       };
      };
    };
  };
}
