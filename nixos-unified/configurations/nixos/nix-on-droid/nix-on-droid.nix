# nix-on-droid switch --flake .
{
  config,
  lib,
  pkgs,
  ...
}:

{
  system.stateVersion = "24.05";
  # stylix = {
  #   enable = true;
  # };

  user = {
    # userName = "mfarabi";
    shell = "${pkgs.zsh}/bin/zsh";
  };

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
      trusted-users = root mfarabi
    '';
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://cache.lix.systems"
      "https://nix-darwin.cachix.org"
      "https://mfarabi.cachix.org"
      "https://cachix.cachix.org"
      "https://emacs-ci.cachix.org"
      "https://emacsng.cachix.org"
      "https://nixvim.cachix.org"
      "https://nix-on-droid.cachix.org"
      "https://fuellabs.cachix.org"
    ];

    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
      "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
      "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
      "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
      "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
      "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
      "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
      "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
      "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
    ];
  };

  # nixpkgs = {
  # config = {
  # allowBroken = true;
  # };
  # };
}
