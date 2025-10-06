{
  imports = [ ../../modules/shared/nix ];

  nix = {
    channel.enable = false;
    optimise = {
      automatic = true;
      # dates = "daily";
      # persistent = true;
    };
    gc = {
      automatic = true;
      # persistent = true;
      # dates = "daily";
      # options = "";
    };

    settings = {
      max-jobs = "auto";
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://nix-darwin.cachix.org"
        "https://nix-on-droid.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
        "https://emacsng.cachix.org"
      ];

      trusted-substituters = [
        "https://nix-darwin.cachix.org"
        "https://nix-on-droid.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
        "https://emacsng.cachix.org"
      ];

      trusted-public-keys = [
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
        "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
      ];

      extra-substituters = [
        "https://numtide.cachix.org"
        "https://nix-darwin.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
        "https://nix-on-droid.cachix.org"
        "https://emacsng.cachix.org"
      ];

      extra-trusted-public-keys = [
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
        "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
      ];
    };
  };
}
