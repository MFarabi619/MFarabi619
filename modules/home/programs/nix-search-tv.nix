{
  programs.nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;

    settings = {
      update_interval = "1h";
      enable_waiting_message = true;

      indexes = [
        "nur"
        "nixos"
        "darwin"
        "nixpkgs"
        "home-manager"
        # "nixos-wsl"
        # "nixos-raspberry-pi"
      ];

      experimental = {
        render_docs_indexes = {
          # nixos-wsl = "https://nix-community.github.io/NixOS-WSL/options.html";
          nix-on-droid = "https://nix-community.github.io/nix-on-droid/nix-on-droid-options.html";
        };
      };
    };
  };
}
