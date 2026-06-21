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

  # imports = map (path: ./config + path) [ "/services" ];
  # env.PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_26}/bin/node";

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

  scripts = {
    up.exec = ''devenv up "$@"'';
    clean.exec = "git clean -fdX";
    run.exec = ''devenv tasks run "$@" -m before'';
    docs.exec = "bunx likec4 start ${config.git.root}/docs";
    tio.exec = ''HOME="$DEVENV_ROOT" ${pkgs.tio}/bin/tio "$@"'';
  };

  languages = rec {
    nix.enable = true;
    shell.enable = true;
    python.enable = false;
    python.uv.enable = true;

    c.enable = true;
    cplusplus.enable = true;

    rust = {
      enable = false;
      toolchainFile = ./rust-toolchain.toml;
    };

    typescript.enable = false;
    javascript = {
      bun.enable = true;
      package = pkgs.nodejs_26;
      enable = typescript.enable;
    };

    ruby = {
      enable = false;
      bundler.enable = true;
      documentation.enable = true;
    };
  };

  # processes = {
  #   # "cargo:loco:watch" = {
  #   #   exec = "cargo loco watch";
  #   #   ports.http.allocate = config.languages.rust.loco.config.development.server.port;
  #   #   process-compose = {
  #   #     is_tty = true;
  #   #     namespace = "🧩 API";
  #   #   };
  #   # };
  # }
  # //
  #   builtins.mapAttrs
  #     (_: cfg: {
  #       process-compose = {
  #         is_tty = true;
  #         namespace = "🎡 SERVICES";
  #       };
  #     })
  #     {
  #       sqld.enable = false;
  #       caddy.enable = true;
  #       mailpit.enable = true;
  #       prometheus.enable = false;
  #       "tailscale-funnel".enable = false;
  #     }
  # // lib.optionalAttrs (!config.devenv.isTesting) {
  #   console = {
  #     exec = ''
  #       ttyd --writable --browser --url-arg --once devenv up
  #     '';
  #     process-compose = {
  #       disabled = true;
  #       namespace = "🧮 VIEWS";
  #       description = "🕹 Attach the Microvisor Kernel to the Browser";
  #     };
  #   };
  # };

  # profiles =
  #   { }
  #   // lib.optionalAttrs config.services.postgres.enable {
  #     user."mfarabi".module.env = {
  #       # BASE_URL = "mfarabi.sh";
  #       EXERCISM_API_URL = "https://api.exercism.org/v1";
  #     };
  #   };

  # certificates = [ "*.localhost" ];
  # hosts = lib.genAttrs (lib.attrNames config.services.caddy.virtualHosts) (_: "127.0.0.1");

  # services = {
  #   mailpit.enable = !(pkgs.stdenv.isLinux && pkgs.stdenv.isAarch64);

  #   caddy =
  #     let
  #       common = ''
  #         log
  #         encode zstd gzip
  #         tls ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost.pem ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost-key.pem
  #       '';
  #     in
  #     {
  #       enable = true;
  #       config = ''
  #         {
  #           log default {
  #             level INFO
  #             output stdout
  #             format console
  #           }
  #         }
  #       '';

  #       virtualHosts = lib.mkMerge [
  #         (lib.mapAttrs'
  #           (
  #             name: upstream:
  #             lib.nameValuePair "${name}.localhost" {
  #               extraConfig = ''
  #                 ${common}
  #                 reverse_proxy ${toString upstream}
  #               '';
  #             }
  #           )
  #           (
  #             {
  #               mu = "10.0.0.218";
  #             }
  #             // lib.optionalAttrs config.services.prometheus.enable {
  #               prometheus = ":${toString config.services.prometheus.port}";
  #             }
  #             // lib.optionalAttrs config.services.postgres.enable {
  #               postgres = ":${toString config.services.postgres.port}";
  #             }
  #             // lib.optionalAttrs config.services.mailpit.enable {
  #               mailpit = config.services.mailpit.uiListenAddress;
  #             }
  #             // lib.optionalAttrs config.services.sqld.enable {
  #               sqld = ":${toString config.services.sqld.port}";
  #             }
  #             # // lib.optionalAttrs config.languages.rust.loco.enable {
  #             #   api = "${toString config.languages.rust.loco.config.development.server.binding}:${toString config.languages.rust.loco.config.development.server.port}";
  #             # }
  #           )
  #         )
  #         {
  #           "tui.localhost".extraConfig = ''
  #             ${common}
  #             file_server
  #             root * ${config.git.root}/tui/dist
  #           '';
  #         }
  #         {
  #           "web.localhost".extraConfig = ''
  #             ${common}
  #             file_server
  #             root * ${config.git.root}/target/dx/web/release/web/public
  #           '';
  #         }
  #       ];
  #     };

  #   postgres = {
  #     enable = true;
  #     createDatabase = true;
  #     package = pkgs.postgresql_18;
  #     listen_addresses = "127.0.0.1";

  #     initialDatabases = [
  #       {
  #         name = config.name;
  #         schema = "${config.git.root}/learning/sql/src/schema.sql";
  #       }
  #       {
  #         name = "pulumi";
  #       }
  #     ];

  #     # https://pgtune.leopard.in.ua
  #     settings = {
  #       log_statement = "all";
  #       log_connections = true;
  #       logging_collector = true;
  #       log_disconnections = true;
  #       shared_preload_libraries = "timescaledb,pg_cron";
  #       "cron.database_name" = "microvisor";

  #       # work_mem = "32MB";
  #       # min_wal_size = "2GB";
  #       # max_wal_size = "16GB";
  #       # shared_buffers = "16GB";
  #       # maintenance_work_mem = "4GB";
  #       # effective_cache_size = "64GB";

  #       # random_page_cost = "1.1";
  #       # max_parallel_workers = "6";
  #       # max_worker_processes = "10";
  #       # max_parallel_workers_per_gather = "4";

  #       # datestyle = "iso, mdy";
  #       # lc_time = "en_US.UTF-8";
  #       # lc_numeric = "en_US.UTF-8";
  #       # lc_messages = "en_US.UTF-8";
  #       # lc_monetary = "en_US.UTF-8";
  #       # default_text_search_config = "pg_catalog.english";
  #     };

  #     extensions =
  #       extensions: with extensions; [
  #         pgmq # lightweight message queue
  #         ip4r # ip address typing, formatting, querying, and indexing
  #         pgtap # unit testing
  #         # pgddl
  #         pg_net # async networking and http outbound calls
  #         pg_csv
  #         # pgaudit # FIXME: marked as broken # audit logging
  #         pg_cron # cron jobs
  #         postgis # geospatial types and queries
  #         pgrouting # routing/network analysis on top of postgic
  #         pgvector # vector embedding
  #         pgsodium
  #         wal2json # emit row changes as json
  #         omnigres
  #         pg-semver
  #         pg_uuidv7
  #         pg_partman # table partition management
  #         pgsql-http # synchronous http request/response client
  #         pointcloud # point cloud/LiDAR data
  #         # pg_graphql # FIXME: pg_graphql-1.5.12-unstable-2025-09-01 marked as broken
  #         # sqlite_fdw # FIXME: sqlite_fdw-2.5.0 marked as broken
  #         pg_rational # extract fraction arithmetic
  #         pg_relusage # trace relations traversed by statement
  #         timescaledb
  #         system_stats
  #         pg_hint_plan # influence planner choices with SQL hints in comments
  #         pg_byteamagic # auto-identify bytea blob file types
  #         pg_background
  #         plpgsql_check # linter
  #         jsonb_deep_sum # sum deeply nested numeric values
  #         # pg_auto_failover # FIXME: pg_auto_failover-2.2 marked as broken
  #         # timescaledb_toolkit # FIXME: timescaledb_toolkit-1.21.0 marked as broken
  #       ];

  #     hbaConf = ''
  #       # PostgreSQL Client Authentication Configuration File
  #       # ===================================================
  #       #
  #       # Refer to the "Client Authentication" section in the PostgreSQL
  #       # documentation for a complete description of this file.  A short
  #       # synopsis follows.
  #       #
  #       # ----------------------
  #       # Authentication Records
  #       # ----------------------
  #       #
  #       # This file controls: which hosts are allowed to connect, how clients
  #       # are authenticated, which PostgreSQL user names they can use, which
  #       # databases they can access.  Records take one of these forms:
  #       #
  #       # local         DATABASE  USER  METHOD  [OPTIONS]
  #       # host          DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
  #       # hostssl       DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
  #       # hostnossl     DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
  #       # hostgssenc    DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
  #       # hostnogssenc  DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
  #       #
  #       # (The uppercase items must be replaced by actual values.)
  #       #
  #       # The first field is the connection type:
  #       # - "local" is a Unix-domain socket
  #       # - "host" is a TCP/IP socket (encrypted or not)
  #       # - "hostssl" is a TCP/IP socket that is SSL-encrypted
  #       # - "hostnossl" is a TCP/IP socket that is not SSL-encrypted
  #       # - "hostgssenc" is a TCP/IP socket that is GSSAPI-encrypted
  #       # - "hostnogssenc" is a TCP/IP socket that is not GSSAPI-encrypted
  #       #
  #       # DATABASE can be "all", "sameuser", "samerole", "replication", a
  #       # database name, a regular expression (if it starts with a slash (/))
  #       # or a comma-separated list thereof.  The "all" keyword does not match
  #       # "replication".  Access to replication must be enabled in a separate
  #       # record (see example below).
  #       #
  #       # USER can be "all", a user name, a group name prefixed with "+", a
  #       # regular expression (if it starts with a slash (/)) or a comma-separated
  #       # list thereof.  In both the DATABASE and USER fields you can also write
  #       # a file name prefixed with "@" to include names from a separate file.
  #       #
  #       # ADDRESS specifies the set of hosts the record matches.  It can be a
  #       # host name, or it is made up of an IP address and a CIDR mask that is
  #       # an integer (between 0 and 32 (IPv4) or 128 (IPv6) inclusive) that
  #       # specifies the number of significant bits in the mask.  A host name
  #       # that starts with a dot (.) matches a suffix of the actual host name.
  #       # Alternatively, you can write an IP address and netmask in separate
  #       # columns to specify the set of hosts.  Instead of a CIDR-address, you
  #       # can write "samehost" to match any of the server's own IP addresses,
  #       # or "samenet" to match any address in any subnet that the server is
  #       # directly connected to.
  #       #
  #       # METHOD can be "trust", "reject", "md5", "password", "scram-sha-256",
  #       # "gss", "sspi", "ident", "peer", "pam", "ldap", "radius" or "cert".
  #       # Note that "password" sends passwords in clear text; "md5" or
  #       # "scram-sha-256" are preferred since they send encrypted passwords.
  #       #
  #       # OPTIONS are a set of options for the authentication in the format
  #       # NAME=VALUE.  The available options depend on the different
  #       # authentication methods -- refer to the "Client Authentication"
  #       # section in the documentation for a list of which options are
  #       # available for which authentication methods.
  #       #
  #       # Database and user names containing spaces, commas, quotes and other
  #       # special characters must be quoted.  Quoting one of the keywords
  #       # "all", "sameuser", "samerole" or "replication" makes the name lose
  #       # its special character, and just match a database or username with
  #       # that name.
  #       #
  #       # ---------------
  #       # Include Records
  #       # ---------------
  #       #
  #       # This file allows the inclusion of external files or directories holding
  #       # more records, using the following keywords:
  #       #
  #       # include           FILE
  #       # include_if_exists FILE
  #       # include_dir       DIRECTORY
  #       #
  #       # FILE is the file name to include, and DIR is the directory name containing
  #       # the file(s) to include.  Any file in a directory will be loaded if suffixed
  #       # with ".conf".  The files of a directory are ordered by name.
  #       # include_if_exists ignores missing files.  FILE and DIRECTORY can be
  #       # specified as a relative or an absolute path, and can be double-quoted if
  #       # they contain spaces.
  #       #
  #       # -------------
  #       # Miscellaneous
  #       # -------------
  #       #
  #       # This file is read on server startup and when the server receives a
  #       # SIGHUP signal.  If you edit the file on a running system, you have to
  #       # SIGHUP the server for the changes to take effect, run "pg_ctl reload",
  #       # or execute "SELECT pg_reload_conf()".
  #       #
  #       # ----------------------------------
  #       # Put your actual configuration here
  #       # ----------------------------------
  #       #
  #       # If you want to allow non-local connections, you need to add more
  #       # "host" records.  In that case you will also need to make PostgreSQL
  #       # listen on a non-local interface via the listen_addresses
  #       # configuration parameter, or via the -i or -h command line switches.

  #       # CAUTION: Configuring the system for local "trust" authentication
  #       # allows any local user to connect as any PostgreSQL user, including
  #       # the database superuser.  If you do not trust all your local users,
  #       # use another authentication method.

  #       # TYPE  DATABASE        USER            ADDRESS                 METHOD

  #       # "local" is for Unix domain socket connections only
  #       local   all             all                                     trust
  #       # IPv4 local connections:
  #       host    all             all             127.0.0.1/32            trust
  #       # IPv6 local connections:
  #       host    all             all             ::1/128                 trust
  #       # Allow replication connections from localhost, by a user with the
  #       # replication privilege.
  #       local   replication     all                                     trust
  #       host    replication     all             127.0.0.1/32            trust
  #       host    replication     all             ::1/128                 trust
  #       # FIXME: LAN connections
  #       host    ${config.name}  mfarabi         100.86.57.35/32         trust
  #     '';
  #   };

  #   sqld = {
  #     enable = true;
  #     extraArgs = [
  #       "--enable-http-console"
  #       "--db-path=${config.git.root}/config/data.sqld"
  #     ];
  #   };

  #   tailscale.funnel = {
  #     enable = true;
  #     target = "${toString config.services.prometheus.port}";
  #   };

  #   prometheus = {
  #     enable = true;
  #     globalConfig = {
  #       scrape_interval = "15s";
  #       evaluation_interval = "15s";
  #     };

  #     scrapeConfigs = [
  #       {
  #         job_name = "prometheus";
  #         static_configs = [
  #           {
  #             targets = [
  #               "localhost:${toString config.services.prometheus.port}"
  #             ];
  #           }
  #         ];
  #       }
  #       {
  #         job_name = "sqld";
  #         static_configs = [
  #           {
  #             targets = [
  #               "localhost:${toString config.services.sqld.port}"
  #             ];
  #           }
  #         ];
  #       }
  #     ];
  #   };
  # };

  # android = lib.mkIf dioxus.mobile.android.enable {
  #   enable = true;
  #   ndk.enable = true;
  #   emulator.enable = true;
  #   android-studio.enable = true;
  # };
}
