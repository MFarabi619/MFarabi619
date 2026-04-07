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

      libyaml
      trunk # rust web app server
      rustywind
    ]
    ++ lib.optionals config.languages.ruby.enable [
      # rails new --help
      rubyPackages_3_4.rails # rails new store -Gc tailwind --skip-ci
    ]
    ++ lib.optionals config.services.postgres.enable [
      # postgresql_18 # for emacs to access `psql`
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ];
}
