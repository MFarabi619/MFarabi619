{
  lib,
  pkgs,
  config,
  ...
}:
{
  packages =
    with pkgs;
    [
      sqlite
      # duckdb
      supabase-cli

      trunk # rust web app server

      pulumi
      pulumi-esc
      # pulumiPackages.pulumi-go
    ]
    ++ lib.optionals config.services.postgres.enable [
      # postgresql_18 # for emacs to access `psql`
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      # macmon
    ];
}
