{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  packages =
    with pkgs;
    [
      duckdb
      harlequin

      # espup install # . $HOME/export-esp.sh
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

      pulumi
      pulumi-esc
      pulumiPackages.pulumi-go

      supabase-cli

      # dioxus-cli
      sqlite
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      # macmon
    ];
}
