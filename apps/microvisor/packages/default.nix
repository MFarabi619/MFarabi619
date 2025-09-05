{ inputs, pkgs, lib, ... }:

# let
#   fuel-nix = inputs.fuel-nix.packages.${pkgs.system};
# in
{
  imports = [
    # ./ai.nix
  ];

  packages =
    with pkgs;
    [
      trunk # rust web app server

      pulumi-esc
      supabase-cli

      # fuel-nix.forc
      # fuel-nix.fuel-core
    ]
    ++ lib.optionals (stdenv.isLinux) [
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      macmon
    ];
}
