{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.languages.rust.dioxus = {
    enable = lib.mkEnableOption "Dioxus (Rust) development stack";
    desktop.linux.enable = lib.mkEnableOption "Dioxus desktop stack for GNU/Linux (glib, atk, gtk, webkitgtk, openssl, etc.)";
    mobile.android.enable = lib.mkEnableOption "Dioxus mobile stack for Android (SDK+NDK+Emulator+Studio + Rust targets)";

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

  config = lib.mkIf config.languages.rust.dioxus.enable {
    assertions = [
      {
        assertion = (!config.languages.rust.dioxus.desktop.linux.enable) || pkgs.stdenv.isLinux;
        message = "languages.rust.dioxus.desktop.linux.enable is true, but this system is not Linux. Disable it (or make it conditional) on Darwin/other platforms.";
      }
    ];

    packages =
      (with pkgs; [
        binaryen
        dioxus-cli
        tailwindcss_4
        wasm-bindgen-cli_0_2_105
      ])
      ++ lib.optionals pkgs.stdenv.isLinux (
        with pkgs;
        [
          openssl
        ]
      )
      ++ lib.optionals (config.languages.rust.dioxus.desktop.linux.enable && pkgs.stdenv.isLinux) (
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
      ++ config.languages.rust.dioxus.extraPackages;

    languages.rust.targets = [
      "wasm32-unknown-unknown"
    ]
    ++ lib.optionals config.languages.rust.dioxus.mobile.android.enable [
      "i686-linux-android"
      "x86_64-linux-android"
      "aarch64-linux-android"
      "armv7-linux-androideabi"
    ]
    ++ config.languages.rust.dioxus.extraTargets;

    android = lib.mkIf config.languages.rust.dioxus.mobile.android.enable {
      enable = true;
      ndk.enable = true;
      emulator.enable = true;
      android-studio.enable = true;
    };
  };
}
