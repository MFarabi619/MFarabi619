{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  name = "mfarabi-dev-env";

  languages = {
    shell.enable = true;
    nix.enable = true;
    rust = {
      enable = true;
      channel = "stable";
      targets = [ "wasm32-unknown-unknown" ];
      components = [ "rustc" "cargo" "clippy" "rustfmt" "rust-analyzer"];
    };
    javascript = {
      enable = true;
      package = pkgs.nodejs_22;
      # bun = {
        #   enable = true;
        #   install.enable = true;
        # };
        pnpm = {
          enable = true;
        };
    };
    typescript.enable = true;
    python = {
      enable = true;
      uv.enable = true;
    };
    ruby = { # needed for lolcat
      enable = true;
      bundler.enable = true;
    };
  };

  starship = {
    enable = true;
    config = {
        enable = true;
        path = "${config.env.DEVENV_ROOT}/libs/dotfiles/.config/starship/gruvbox-rainbow.toml";
      };
  };

  # let
    #   rosettaPkgs = pkgs.pkgsx86_64Darwin;
    # in {
      packages =  with pkgs; [
        # ============= 🧑‍💻🐞‍ ================
        vim
        neovim
        zellij
        nerd-fonts.jetbrains-mono
        git
        gh
        btop
        lazygit
        lazysql
        yazi
        shellspec
        docker
        lazydocker
        supabase-cli
        pik
        moon
        uv
        termshark
        ttyd
        trunk                     # rust web app server
        tgpt
        ncdu
        nix-tree
        # ============== 🤪 =================
        asciiquarium
        bat
        eza
        ascii-image-converter
        # chafa
        ansi
        glibcLocales
        ncurses
        figlet
        lolcat
        fastfetch
      ] ++ lib.optionals stdenv.isLinux [
        inotify-tools
      ] ++ lib.optionals stdenv.isDarwin [
        libiconv
      ];
      #   ++ lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) [
        #     rosettaPkgs.dmd
        #   ];
        # }

        process.manager.args = {"theme"="One Dark";};

        # github.com/cachix/devenv/blob/main/src/modules/process-managers/process-compose.nix
        process.managers.process-compose = {
          settings = {
          processes = {
            api = {
            #   process-compose = {
            # log_configuration = {
            # fields_order = ["level" "message" "time"];
            # };
            #   };
              description = "Back-End Server using Loco.rs";
              is_tty = true;
              command = "moon run api:start";
              depends_on = {
                  postgres.condition = "process_healthy";
              };
              readiness_probe = {
                http_get = {
                  port = "5150";
                  host = "localhost";
                  scheme = "http";
                };
              };
              namespace = "⚙ Back-End";
            };
            web = {
            log_configuration = {
            fields_order = ["level" "message" "time"];
            };
              description = "Front-End Server using Dioxus";
              is_tty = true;
              command = "moon run web:serve";
              depends_on = {
                  api.condition = "process_healthy";
              };
              readiness_probe = {
                http_get = {
                  port = "8080";
                  host = "localhost";
                  scheme = "http";
                };
              };
              namespace = "✨ Front-End";
            };
            # depends_on.some-other-process.condition = {
            #           "process_completed_successfully";
            #       };
            cargo-watch = {
              command = "cargo-watch";
              disabled = true;
              namespace = "⚒ Tooling";
              ready_log_line = "[Finished running. Exit Status: 0]";
            };

            moonrepo-action-graph = {
              command = "moon action-graph";
              disabled = true;
              namespace = "🌕 Build System";
              ready_log_line = "Started server on http://";
            };

            moonrepo-task-graph = {
              command = "moon task-graph";
              disabled = true;
              namespace = "🌕 Build System";
              ready_log_line = "Started server on http://";
            };

            moonrepo-project-graph = {
              command = "moon project-graph";
              disabled = true;
              namespace = "🌕 Build System";
              ready_log_line = "Started server on http://";
            };

            asciiquarium = {
              is_tty = true;
              command = "asciiquarium";
              disabled = true;
              namespace = "⚒ Tooling";
            };
          };
            availability = {
              restart = "on_failure";
              backoff_seconds = 2;
              max_restarts = 5;
            };
            # environment = [
            #   "ENVVAR_FOR_THIS_PROCESS_ONLY=foobar"
            # ];
          };
        };

        services = {
          postgres = {
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

        # kafka = {enable = true; };
        # redis = {
          # enable = true;
          # bind = "127.0.0.1";
          # extraConfig = "";
          # port = 6379;
        # };
        # mongodb = {
        #   enable = true;
        #   #  additionalArgs = [
        #     # "--port"
        #     # "27017"
        #     # "--noauth"
        #     #  ];
        #     initDatabaseUsername = "mongodb";
        #     initDatabasePassword = "mongodb";
        # };
        # nginx = {
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
            # eslint.enable = true;
            # cargo-check.enable = true;
            check-json.enable = true;
            # check-toml.enable = true;
            # check-yaml.enable = true;
            # commitizen.enable = true;
            # eclint.enable = true;
            # html-tidy.enable = true;
            # rustfmt.enable = true;
            # clippy.enable = true;
            actionlint.enable = true;
          };

          # devcontainer.enable = true;
          # NOTE: Existing env variables set in devenv.nix will have priority.
          dotenv = {
            enable = true;
            filename = [
              ".env"
              # ".env.development"
              # ".env.production"
            ];
          };

          env = {
            GREET = "devenv";
            #====================================================
            #                      FLAGS
            #====================================================
            # SUPABASE=true; # Requires Docker
            # SQLITE=true;
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
}
