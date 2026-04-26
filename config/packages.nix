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
      grafana
      grafanactl
      mcp-grafana # https://github.com/grafana/mcp-grafana
    ]
    ++ [
      sqlite
      supabase-cli
    ]
    ++ [
      trunk # rust web app server
      rustywind
    ]
    ++ [
      SDL2 # for embedded TUI simulator
      espup
      ninja
      ccache
      rustup
      esptool
      openocd
      ldproxy
      espflash
      esp-generate
      cargo-embassy
      cargo-generate
      (probe-rs-tools.overrideAttrs (old: {
        cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "remote" ];
      }))
    ]
    ++ lib.optionals config.languages.ruby.enable [
      # rails new --help
      libyaml
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
