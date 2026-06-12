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

  imports = map (path: ./config + path) [
    "/services"
  ];

  env.PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_25}/bin/node";

  packages =
    with pkgs-unstable;
    [ ]
    ++ lib.optionals config.languages.ruby.enable [
      libyaml # rails new --help
      rubyPackages_3_4.rails # rails new store -Gc tailwind --skip-ci
    ]
    ++ lib.optionals stdenv.isDarwin [ ]
    ++ lib.optionals stdenv.isLinux [ ];

  # packages =
  #   (with pkgs-unstable; [
  #     binaryen
  #     dioxus-cli
  #     tailwindcss_4
  #     cargo-binstall
  #     # FIXME: nixpkgs behind on latest
  #     # use `cargo binstall wasm-bindgen-cli@0.2.116`
  #   ])
  #   ++ lib.optionals pkgs.stdenv.isLinux (
  #     with pkgs-unstable;
  #     [
  #       openssl
  #     ]
  #   )
  #   ++ lib.optionals (dioxus.desktop.linux.enable && pkgs.stdenv.isLinux) (
  #     with pkgs-unstable;
  #     [
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
  #     ]
  #   );

  scripts = {
    up.exec = ''devenv up "$@"'';
    clean.exec = "git clean -fdX";
    run.exec = ''devenv tasks run "$@" -m before'';
    docs.exec = "bunx likec4 start ${config.git.root}/docs";
  };

  processes = {
    # "cargo:loco:watch" = {
    #   exec = "cargo loco watch";
    #   ports.http.allocate = config.languages.rust.loco.config.development.server.port;
    #   process-compose = {
    #     is_tty = true;
    #     namespace = "🧩 API";
    #   };
    # };
  }
  //
    builtins.mapAttrs
      (_: cfg: {
        process-compose = {
          is_tty = true;
          namespace = "🎡 SERVICES";
        };
      })
      {
        sqld.enable = false;
        caddy.enable = true;
        mailpit.enable = true;
        prometheus.enable = false;
        "tailscale-funnel".enable = false;
      }
  // lib.optionalAttrs (!config.devenv.isTesting) {
    console = {
      exec = ''
        ttyd --writable --browser --url-arg --once devenv up
      '';
      process-compose = {
        disabled = true;
        namespace = "🧮 VIEWS";
        description = "🕹 Attach the Microvisor Kernel to the Browser";
      };
    };
  };

  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        # BASE_URL = "mfarabi.sh";
        EXERCISM_API_URL = "https://api.exercism.org/v1";
      };
    };

  cachix = {
    enable = true;
    pull =
      [ ]
      ++ lib.optionals config.languages.rust.enable [
        "oxalica"
      ];
  };

  languages = rec {
    nix.enable = true;
    shell.enable = true;
    python.enable = false;
    python.uv.enable = true;

    c.enable = true;
    c.debugger = pkgs.gdb;
    cplusplus.enable = true;

    rust = {
      enable = false;
      toolchainFile = ./rust-toolchain.toml;
    };

    typescript.enable = false;
    javascript = {
      bun.enable = true;
      package = pkgs.nodejs_25;
      enable = typescript.enable;
    };

    ruby = {
      enable = false;
      bundler.enable = true;
      documentation.enable = true;
    };
  };

  # android = lib.mkIf dioxus.mobile.android.enable {
  #   enable = true;
  #   ndk.enable = true;
  #   emulator.enable = true;
  #   android-studio.enable = true;
  # };
}
