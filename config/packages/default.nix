{
  inputs,
  pkgs,
  lib,
  ...
}:

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
      # espup install
      # . $HOME/export-esp.sh
      espup
      esptool
      espflash
      binsider # binary inspector TUI
      esp-generate
      cargo-espmonitor

      ninja
      ccache
      dfu-util

      trunk # rust web app server

      pulumi-esc
      supabase-cli

      # fuel-nix.forc
      # fuel-nix.fuel-core
      # dioxus-cli
      sqlite
    ]
    ++ lib.optionals (stdenv.isLinux) [
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      macmon
    ];
}
