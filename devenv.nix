{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  # api = config.languages.rust.import ./. { };
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  name = "microvisor";
  cachix.pull = lib.optionals config.languages.rust.enable [ "oxalica" ];

  imports = map (path: ./config + path) [
    # "/services"
    "/languages"

    "/env.nix"
    "/tasks.nix"
    "/scripts.nix"
    # "/profiles.nix"
    "/processes.nix"
  ];

  packages =
    (
      with pkgs-unstable;
      [
        #     binaryen
        #     dioxus-cli
        #     tailwindcss_4
        #     cargo-binstall
        #     # FIXME: nixpkgs behind on latest
        #     # use `cargo binstall wasm-bindgen-cli@0.2.116`
      ]
      ++ lib.optionals config.languages.ruby.enable [
        libyaml # rails new --help
        rubyPackages_3_4.rails # rails new store -Gc tailwind --skip-ci
      ]
    )
    ++ lib.optionals pkgs.stdenv.isDarwin [ ]
    ++ lib.optionals pkgs.stdenv.isLinux (
      with pkgs-unstable;
      [
        openssl
        #       atk
        #       glib
        #       file
        #       cairo
        #       pango
        #       xdotool
        #       librsvg
        #       gdk-pixbuf
        #       pkg-config
        #       webkitgtk_4_1
        #       libappindicator-gtk3
      ]
    );

  enterTest = ''
    devenv tasks run build
  '';

  # android = lib.mkIf dioxus.mobile.android.enable {
  #   enable = true;
  #   ndk.enable = true;
  #   emulator.enable = true;
  #   android-studio.enable = true;
  # };
}
