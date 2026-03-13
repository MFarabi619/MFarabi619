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
      sqlite
      duckdb
      supabase-cli

      ninja
      ccache
      dfu-util

      trunk # rust web app server

      pulumi
      pulumi-esc
      # pulumiPackages.pulumi-go
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      # macmon
    ];
}
