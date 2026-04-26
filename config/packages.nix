{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  packages =
    with pkgs-unstable;
    [
      pulumi
      pulumi-esc
    ]
    ++ [
      sqlite
      # duckdb
      supabase-cli

      libyaml
      trunk # rust web app server
      rustywind
    ]
    ++ [
      ninja
      ccache
      openocd
      esptool
    ]
    ++ lib.optionals config.languages.ruby.enable [
      # rails new --help
      rubyPackages_3_4.rails # rails new store -Gc tailwind --skip-ci
    ]
    ++ lib.optionals stdenv.isDarwin [
      binsider
      dfu-util
      kconfig-frontends
      python314Packages.kconfiglib
    ]
    ++ lib.optionals stdenv.isLinux [
      # netscanner
    ];
}
