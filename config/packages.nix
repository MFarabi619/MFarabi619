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
    ]
    ++ lib.optionals config.services.postgres.enable [
      # postgresql_18 # for emacs to access `psql`
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ];
}
