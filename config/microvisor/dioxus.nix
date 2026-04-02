{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let

  dioxus = config.languages.rust.dioxus;
  default_config_file = "${config.git.root}/Dioxus.toml";
  final_config_file = lib.defaultTo default_config_file dioxus.configFile;
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };

  removeNulls =
    v:
    if builtins.isAttrs v then
      let
        cleaned = lib.mapAttrs (_: val: removeNulls val) v;
      in
      lib.filterAttrs (_: val: val != null && !(builtins.isAttrs val && val == { })) cleaned
    else if builtins.isList v then
      map removeNulls v
    else
      v;

  typed_toml = {
    application = dioxus.application;
    web = dioxus.web;
    bundle = dioxus.bundle;
  };

  final_toml = removeNulls (lib.recursiveUpdate typed_toml dioxus.extra_config);
in
{
  options.languages.rust.dioxus = {
    enable = lib.mkEnableOption "Dioxus (Rust) development stack";
    desktop.linux.enable = lib.mkEnableOption "Dioxus desktop stack for GNU/Linux (glib, atk, gtk, webkitgtk, openssl, etc.)";
    mobile.android.enable = lib.mkEnableOption "Dioxus mobile stack for Android (SDK+NDK+Emulator+Studio + Rust targets)";

    writeConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to generate Dioxus.toml.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to Dioxus.toml. Defaults to `${default_config_file}`.";
    };

    application = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = {
          tailwind_input = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          tailwind_output = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      };
    };

    web = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = {
          app = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                title = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
              };
            };
          };
        };
      };
    };

    bundle = lib.mkOption {
      default = { };
      type = lib.types.submodule {
        options = {
          category = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          publisher = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          icon = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
          };
          identifier = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          copyright = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          short_description = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      };
    };

    extra_config = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Deep-merged into generated Dioxus.toml after typed config.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages to add when Dioxus stack is enabled.";
    };

    extraTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra rust targets to add when Dioxus stack is enabled.";
    };
  };

  config = lib.mkIf dioxus.enable {
    assertions = [
      {
        assertion = (!dioxus.desktop.linux.enable) || pkgs.stdenv.isLinux;
        message = "languages.rust.dioxus.desktop.linux.enable is true, but this system is not Linux. Disable it (or make it conditional) on Darwin/other platforms.";
      }
      {
        assertion = (!dioxus.writeConfig) || final_config_file != null;
        message = "languages.rust.dioxus.writeConfig is true, but configFile resolved to null.";
      }
    ];

    packages =
      (with pkgs; [
        binaryen
        tailwindcss_4
        cargo-binstall
        # FIXME: nixpkgs behind on latest, still on dx 0.7.3 and missing wasm-bindgen-cli_0_2_116
        # use `cargo binstall wasm-bindgen-cli@0.2.116 dioxus-cli@0.7.4`
        # dioxus-cli
        # pkgs-unstable.wasm-bindgen-cli_0_2_114
      ])
      ++ lib.optionals pkgs.stdenv.isLinux (
        with pkgs;
        [
          openssl
        ]
      )
      ++ lib.optionals (dioxus.desktop.linux.enable && pkgs.stdenv.isLinux) (
        with pkgs;
        [
          atk
          glib
          file
          cairo
          pango
          xdotool
          librsvg
          gdk-pixbuf
          pkg-config
          webkitgtk_4_1
          libappindicator-gtk3
        ]
      )
      ++ dioxus.extraPackages;

    files = lib.mkIf dioxus.writeConfig {
      "${final_config_file}".toml = final_toml;
    };

    languages.rust.targets = [
      "wasm32-unknown-unknown"
    ]
    ++ lib.optionals dioxus.mobile.android.enable [
      "i686-linux-android"
      "x86_64-linux-android"
      "aarch64-linux-android"
      "armv7-linux-androideabi"
    ]
    ++ dioxus.extraTargets;

    android = lib.mkIf dioxus.mobile.android.enable {
      enable = true;
      ndk.enable = true;
      emulator.enable = true;
      android-studio.enable = true;
    };
  };
}
