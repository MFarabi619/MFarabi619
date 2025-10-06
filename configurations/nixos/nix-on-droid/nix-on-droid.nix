# nix-on-droid switch --flake .
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../../../modules/shared/nix ];

  system.stateVersion = "24.05";
  # stylix = {
  #   enable = true;
  # };

  user = {
    # home = "mfarabi";
    # group = "mfarabi";
    # userName = "mfarabi";
    shell = "${pkgs.zsh}/bin/zsh";
  };

  nix = {
    extraOptions = ''
      trusted-users = root mfarabi
      experimental-features = nix-command flakes
    '';

    substituters = [
      "https://nix-darwin.cachix.org"
      "https://emacsng.cachix.org"
      "https://nix-on-droid.cachix.org"
    ];

    trustedPublicKeys = [
      "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
      "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
      "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
    ];
  };

  # nixpkgs = {
  # config = {
  # allowBroken = true;
  # };
  # };
}
