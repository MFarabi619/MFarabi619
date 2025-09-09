{
  nix = {
    channel.enable = false;

    distributedBuilds = true;
    # distributedBuilds.enable = true;
    buildMachines = [
      {
        maxJobs = 100;
        sshUser = null;
        speedFactor = 1;
        # protocol = "ssh-ng";
        hostName = "eu.nixbuild.net";
        sshKey = "~/.ssh/id_ed25519";
        systems = [
          "x86_64-linux"
          # "aarch64-darwin"
        ];
        supportedFeatures = [
          "benchmark"
          "big-parallel"
        ];
        publicHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
        #     mandatoryFeatures = [ "big-parallel" ];
      }
    ];
    settings = {
      max-jobs = "auto";
      # auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://cache.nixos.org"
        "https://cache.lix.systems"
        "https://nix-community.cachix.org"

        "https://nixpkgs.cachix.org"
        "https://cachix.cachix.org"
        "https://devenv.cachix.org"

        "https://nix-darwin.cachix.org"
        "https://nix-on-droid.cachix.org"
        "https://nixos-raspberrypi.cachix.org"

        "https://mfarabi.cachix.org"
        "https://fuellabs.cachix.org"
        "https://charthouse-labs.cachix.org"

        "https://emacsng.cachix.org"
        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"

        "https://hyprland.cachix.org"
      ];

      trusted-substituters = [
        "https://cache.nixos.org"
        "https://cache.lix.systems"
        "https://nix-community.cachix.org"

        "https://nixpkgs.cachix.org"
        "https://cachix.cachix.org"
        "https://devenv.cachix.org"

        "https://nix-darwin.cachix.org"
        "https://nixos-raspberrypi.cachix.org"

        "https://charthouse-labs.cachix.org"
        "https://mfarabi.cachix.org"
        "https://fuellabs.cachix.org"

        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"

        "https://hyprland.cachix.org"
      ];

      trusted-public-keys = [
        "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "charthouse-labs.cachix.org-1:6R5o8MQocvl45MoSIIWKawTLDqghQjW0arZ/S6+W2AQ="
        "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
        "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
        "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
        "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
        "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];

      extra-substituters = [
        "https://cache.nixos.org"
        "https://cache.lix.systems"
        "https://nix-community.cachix.org"

        "https://cachix.cachix.org"
        "https://devenv.cachix.org"
        "https://nixpkgs.cachix.org"
        "https://numtide.cachix.org"

        "https://nix-darwin.cachix.org"
        "https://nixos-raspberrypi.cachix.org"

        "https://charthouse-labs.cachix.org"
        "https://mfarabi.cachix.org"
        "https://fuellabs.cachix.org"

        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"

        "https://hyprland.cachix.org"
      ];

      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="

        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="

        "charthouse-labs.cachix.org-1:6R5o8MQocvl45MoSIIWKawTLDqghQjW0arZ/S6+W2AQ="
        "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
        "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="

        "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
        "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="

        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };
  };
}
