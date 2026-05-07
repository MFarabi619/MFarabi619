{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
# let
#   # api = config.languages.rust.import ./. { };
#   pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
# in
{
  name = "microvisor";

  infoSections = {
    name = [ "Mumtahin Farabi" ];
  };

  imports = map (path: ./config + path) [
    "/services"
    "/microvisor"
  ];

  env.PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";

  # packages =
  #   with pkgs-unstable;
  #   [ ]
  #   ++ lib.optionals config.languages.ruby.enable [
  #     libyaml # rails new --help
  #     rubyPackages_3_4.rails # rails new store -Gc tailwind --skip-ci
  #   ]
  #   ++ lib.optionals stdenv.isDarwin [ ]
  #   ++ lib.optionals stdenv.isLinux [ ];

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

  enterShell = ''
    export PATH="$HOME/.cargo/bin:$PATH";

    if [ -f "\$\{ESPUP_EXPORT_FILE:-}" ]; then
      . "$ESPUP_EXPORT_FILE"
    elif [ -f "$HOME/export-esp.sh" ]; then
      . "$HOME/export-esp.sh"
    fi

    if command -v xtensa-esp-elf-gcc >/dev/null 2>&1; then
      echo -e "\033[36m[devenv:embassy]:\033[0m\033[32m Espressif Rust toolchain ready 🦀\033[0m"
    else
      echo -e "\033[36m[devenv:embassy]:\033[0m\033[34m xtensa-esp-elf-gcc \033[0m\033[31mtoolchain not found ⚠️\033[0m"
      echo -e "\033[36m[devenv:embassy]:\033[0m\033[33m install with \033[0m\033[35mespup install && direnv allow\033[0m\n"
    fi
  ''
  + lib.optionalString (pkgs.stdenv.isLinux && config.services.caddy.enable) ''
    # sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
  '';

  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        BASE_URL = "mfarabi.sh";
        EXERCISM_API_URL = "https://api.exercism.org/v1";
      };
    };

  cachix = {
    enable = true;
    push = "mfarabi";
    pull = [
      "cachix"
      "oxalica"
      "devenv"
      "nixpkgs"
      "mfarabi"
      "nix-community"
      "pre-commit-hooks"
    ];
  };

  languages = rec {
    nix.enable = true;
    shell.enable = true;
    cplusplus.enable = true;

    c = {
      enable = true;
      debugger = pkgs.gdb;
    };

    rust = {
      enable = true;
      channel = "stable";
      # lld.enable = true;  # FIXME: breaks dioxus
      # mold.enable = true; # FIXME: breaks loco

      components = [
        "rustc"
        "cargo"
        "clippy"
        "rustfmt"
        "rust-std"
        "rust-src"
        "rust-analyzer"
      ];

      dioxus = {
        enable = true;
        desktop.linux.enable = false;
        mobile.android.enable = false;
      };
    };

    python = {
      enable = false;
      uv.enable = true;
    };

    typescript.enable = javascript.enable;

    javascript = {
      enable = true;
      bun.enable = true;
      package = pkgs.nodejs_24;
      # FIXME: find out why this crashes for intel macbooks
      # pnpm.enable = !(pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64);
    };

    ruby = {
      enable = true;
      bundler.enable = true;
      documentation.enable = true;
    };
  };
}
