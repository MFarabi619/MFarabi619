{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  name = "mfarabi-dev-env";
  env = {
    GREET = "devenv";
    #====================================================
    #                      FLAGS
    #====================================================
    # SUPABASE=true; # Requires Docker
    # SQLITE=true;
    # TERM=xterm-256color;
    # ZELLIJ_AUTO_ATTACH=true;
    # ZELLIJ_AUTO_EXIT=true;

    #====================================================
    #                    DATABASE
    #====================================================
    # PGDATA="$PWD/libs/db/data";
    PG_COLOR="always";
    DATABASE_URI="postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    # DATABASE_URI="postgresql://[NAME]:[PASSWORD]@aws-0-us-east-1.pooler.supabase.com:6543/postgres";
    # S3_ACCESS_KEY_ID="";
    # S3_SECRET_ACCESS_KEY="";
    # S3_BUCKET="staging";
    # S3_REGION="us-east-1";
    # S3_ENDPOINT="https://[ID].supabase.co/storage/v1/s3";

    #====================================================
    #                      PORTS
    #====================================================
    WEB_SERVER_PORT="3000";
    API_SERVER_PORT="5150";
    UI_SERVER_PORT="6006";

    #====================================================
    #                      URLS
    #====================================================
    # BASE_URL="https://mfarabi.dev";
    # LOCALHOST_STRING="http://localhost";

    SUPABASE_STUDIO_URL = "$LOCALHOST_STRING:54323";
  };

  # devcontainer.enable = true;
  # dotenv.enable = true;
  # Optionally, you can choose which filename to load.
  # dotenv.filename = ".env.production";
  # or
  # dotenv.filename = [ ".env.production" ".env.development" ]
  # Existing env variables set in devenv.nix will have priority.

  # let
    #   rosettaPkgs = pkgs.pkgsx86_64Darwin;
    # in {
      packages =  with pkgs; [
        vim
        neovim
        git
        eza
        bat
        moon
        zellij
        nerd-fonts.jetbrains-mono
        ascii-image-converter
        asciiquarium
        lazygit
        btop
        yazi
        tgpt
        uv
        shellspec
        fastfetch
        figlet
        lolcat
        ansi
        ncurses
        lazysql
        glibcLocales
        docker
        lazydocker
        supabase-cli
        ttyd
        ncdu
      ] ++ lib.optionals stdenv.isLinux [
        inotify-tools
      ] ++ lib.optionals stdenv.isDarwin [
        libiconv
      ];
      #   ++ lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) [
        #     rosettaPkgs.dmd
        #   ];
        # }

        languages.nix.enable = true;

        languages.rust = {
          enable = true;
          channel = "stable";
          components = [ "rustc" "cargo" "clippy" "rustfmt" "rust-analyzer" ];
        };

        languages.shell.enable = true;

        languages.javascript = {
          enable = true;
          bun = {
            enable = true;
            install.enable = true;
          };
          pnpm = {
            enable = true;
            install.enable = true;
          };
        };
        languages.typescript.enable = true;

        processes.cargo-watch.exec = "cargo-watch";

        process.managers.process-compose = {
          settings = {
            availability = {
              backoff_seconds = 2;
              max_restarts = 5;
              restart = "on_failure";
            };
            # environment = [
            #   "ENVVAR_FOR_THIS_PROCESS_ONLY=foobar"
            # ];
            theme = "Monokai";
          };
          tui.enable = true;
        };

        # https://devenv.sh/services/
        services.postgres = {
          enable = true;
          package = pkgs.postgresql_17;
          listen_addresses = "*";
          port = 54322;
          initialDatabases = [{
            name = "postgres";
            user = "postgres";
            pass = "postgres";
            }];
          # hbaConf = "pg_hba.conf";
          settings = {
            shared_buffers = "128MB";
            dynamic_shared_memory_type = "posix";
            max_wal_size = "1GB";
            min_wal_size = "80MB";
            datestyle = "iso, mdy";
            lc_messages = "en_US.UTF-8";
            lc_monetary = "en_US.UTF-8";
            lc_numeric = "en_US.UTF-8";
            lc_time = "en_US.UTF-8";
            default_text_search_config = "pg_catalog.english";
          };
        };

        # services.kafka = {
        #   enable = true;
        # };

        # services.redis = {
          # enable = true;
          # bind = "127.0.0.1";
          # extraConfig = "";
          # port = 6379;
          # };

          # services.mongodb = {
          #   enable = true;
          #   #  additionalArgs = [
          #     # "--port"
          #     # "27017"
          #     # "--noauth"
          #     #  ];
          #     initDatabaseUsername = "mongodb";
          #     initDatabasePassword = "mongodb";
          # };

          # services.nginx = {
          #   enable = true;
          #   httpConfig = ''
          #     server {
          #     listen 8080;
          #     location / {
          #     return 200 "Hello, world!";
          #     }
          #     }
          #   '';
          # };

          starship.enable = true;
          starship.config = {
            enable = true;
            # path = "${config.env.DEVENV_ROOT}/libs/configs/starship/default/starship.toml";
            path = "${config.env.DEVENV_ROOT}/libs/configs/starship/gruvbox-rainbow/starship.toml";
            # path = "${config.env.DEVENV_ROOT}/libs/configs/starship/jetpack/starship.toml";
            # path = "${config.env.DEVENV_ROOT}/libs/configs/starship/pastel-powerline/starship.toml";
            # path = "${config.env.DEVENV_ROOT}/libs/configs/starship/catppuccin-powerline/starship.toml";
          };

          scripts.hello.exec = ''
            figlet  Hello from $GREET | lolcat
          '';

          enterShell = ''
            alias  l='eza -alh  --icons=auto' # long list
            alias ls='eza -a -1   --icons=auto' # short list
            alias ll='eza -lha --icons=auto --sort=name --group-directories-first' # long list all
            alias ld='eza -lhD --icons=auto' # long list dirs
            alias lt='eza --icons=auto --tree' # list folder as tree
            alias cat='bat'
            alias mkdir='mkdir -p'

            ascii-image-converter ${config.env.DEVENV_ROOT}/libs/assets/devenv-symbol-dark-bg.png --color --complex
            # hello
            echo 👋🧩
          '';

          # https://devenv.sh/tasks/
          # tasks = {
            #   "myproj:setup".exec = "mytool build";
            #   "devenv:enterShell".after = [ "myproj:setup" ];
            # };

            enterTest = ''
              set -ex
              echo "Running tests"
              git --version | grep --color=auto "${pkgs.git.version}"
              wait_for_port 8080
              curl -s localhost:8080 | grep "Hello, world!"
              cargo --version
              rustc --version

              [[ "$CARGO_INSTALL_ROOT" == "$DEVENV_STATE/cargo-install" ]]
              echo "$PATH" | grep -- "$CARGO_INSTALL_ROOT/bin"
              figlet "Tests Passed 🥳" | lolcat
            '';

            # difftastic.enable = true;
            delta.enable = true;
            git-hooks.hooks = {
              # shellcheck.enable = true;
              eslint.enable = true;
              cargo-check.enable = true;
              check-json.enable = true;
              check-toml.enable = true;
              check-yaml.enable = true;
              commitizen.enable = true;
              eclint.enable = true;
              html-tidy.enable = true;
              rustfmt.enable = true;
              clippy.enable = true;
              actionlint.enable = true;
            };
}
