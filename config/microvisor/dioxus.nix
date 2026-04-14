{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
  dioxus = config.languages.rust.dioxus;
in
{
  options.languages.rust.dioxus = {
    enable = lib.mkEnableOption "Dioxus (Rust) development stack";
    desktop.linux.enable = lib.mkEnableOption "Dioxus desktop stack for GNU/Linux (glib, atk, gtk, webkitgtk, openssl, etc.).";
    mobile.android.enable = lib.mkEnableOption "Dioxus mobile stack for Android (SDK+NDK+Emulator+Studio + Rust targets).";

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
    ];

    packages =
      (with pkgs-unstable; [
        binaryen
        dioxus-cli
        tailwindcss_4
        cargo-binstall
        # FIXME: nixpkgs behind on latest
        # use `cargo binstall wasm-bindgen-cli@0.2.116`
      ])
      ++ lib.optionals pkgs.stdenv.isLinux (
        with pkgs-unstable;
        [
          openssl
        ]
      )
      ++ lib.optionals (dioxus.desktop.linux.enable && pkgs.stdenv.isLinux) (
        with pkgs-unstable;
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
