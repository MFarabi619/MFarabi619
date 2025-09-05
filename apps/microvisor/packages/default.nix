{ inputs, pkgs, lib, ... }:

let
  fuel-nix = inputs.fuel-nix.packages.${pkgs.system};
in
{
  imports = [
    ./shell.nix
    # ./ai.nix
  ];

  packages =
    with pkgs;
    [
      supabase-cli

      trunk # rust web app server
      nix-tree

      pulumi
      pulumi-esc
      pulumiPackages.pulumi-nodejs
      pulumiPackages.pulumi-command

      fuel-nix.fuel-core
      fuel-nix.forc
    ]
    ++ lib.optionals (stdenv.isLinux) [
      vips
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      cowsay
    ];
}
