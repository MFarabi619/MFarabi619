{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  name = "microvisor";
  scripts.docs.exec = "bunx likec4 start ${config.git.root}/docs";
  packages = with pkgs-unstable; lib.optionals pkgs.stdenv.isLinux [ openssl ];

  certificates = lib.mkIf config.services.caddy.enable [ "*.localhost" ];
  hosts = lib.mkIf config.services.caddy.enable (
    lib.genAttrs (lib.attrNames config.services.caddy.virtualHosts) (_: "127.0.0.1")
  );

  services = {
    mailpit.enable = false;

    tailscale.funnel = {
      enable = false;
      target = "${toString config.services.prometheus.port}";
    };

    sqld = {
      enable = false;
      extraArgs = [
        "--enable-http-console"
        "--db-path=${config.git.root}/config/data.sqld"
      ];
    };

    prometheus = {
      enable = false;
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };

      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "localhost:${toString config.services.prometheus.port}" ]; } ];
        }
      ]
      ++ lib.optional config.services.sqld.enable {
        job_name = "sqld";
        static_configs = [ { targets = [ "localhost:${toString config.services.sqld.port}" ]; } ];
      };
    };

    caddy =
      let
        common = ''
          log
          encode zstd gzip
          tls ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost.pem ${config.env.DEVENV_STATE}/mkcert/_wildcard.localhost-key.pem
        '';
      in
      {
        enable = false;
        config = ''
          {
            log default {
              level INFO
              output stdout
              format console
            }
          }
        '';

        virtualHosts = lib.mkMerge [
          (lib.mapAttrs'
            (
              name: upstream:
              lib.nameValuePair "${name}.localhost" {
                extraConfig = ''
                  ${common}
                  reverse_proxy ${toString upstream}
                '';
              }
            )
            (
              {
                mu = "10.0.0.218";
              }
              // lib.optionalAttrs config.services.prometheus.enable {
                prometheus = ":${toString config.services.prometheus.port}";
              }
              // lib.optionalAttrs config.services.postgres.enable {
                postgres = ":${toString config.services.postgres.port}";
              }
              // lib.optionalAttrs config.services.mailpit.enable {
                mailpit = config.services.mailpit.uiListenAddress;
              }
              // lib.optionalAttrs config.services.sqld.enable {
                sqld = ":${toString config.services.sqld.port}";
              }
              # // lib.optionalAttrs config.languages.rust.loco.enable {
              #   api = "${toString config.languages.rust.loco.config.development.server.binding}:${toString config.languages.rust.loco.config.development.server.port}";
              # }
            )
          )
          {
            "tui.localhost".extraConfig = ''
              ${common}
              file_server
              root * ${config.git.root}/dist
            '';
          }
          {
            "web.localhost".extraConfig = ''
              ${common}
              file_server
              root * ${config.git.root}/target/dx/web/release/web/public
            '';
          }
        ];
      };

    postgres = {
      enable = false;
      createDatabase = true;
      package = pkgs.postgresql_18;
      listen_addresses = "127.0.0.1";

      initialDatabases = [
        {
          name = config.name;
          schema = "${config.git.root}/learning/sql/src/schema.sql";
        }
        {
          name = "pulumi";
        }
      ];

      # https://pgtune.leopard.in.ua
      settings = {
        log_statement = "all";
        log_connections = true;
        logging_collector = true;
        log_disconnections = true;
        shared_preload_libraries = "timescaledb,pg_cron";
        "cron.database_name" = "microvisor";

        # work_mem = "32MB";
        # min_wal_size = "2GB";
        # max_wal_size = "16GB";
        # shared_buffers = "16GB";
        # maintenance_work_mem = "4GB";
        # effective_cache_size = "64GB";

        # random_page_cost = "1.1";
        # max_parallel_workers = "6";
        # max_worker_processes = "10";
        # max_parallel_workers_per_gather = "4";

        # datestyle = "iso, mdy";
        # lc_time = "en_US.UTF-8";
        # lc_numeric = "en_US.UTF-8";
        # lc_messages = "en_US.UTF-8";
        # lc_monetary = "en_US.UTF-8";
        # default_text_search_config = "pg_catalog.english";
      };

      extensions =
        extensions: with extensions; [
          pgmq # lightweight message queue
          ip4r # ip address typing, formatting, querying, and indexing
          pgtap # unit testing
          # pgddl
          pg_net # async networking and http outbound calls
          pg_csv
          # pgaudit # FIXME: marked as broken # audit logging
          pg_cron # cron jobs
          postgis # geospatial types and queries
          pgrouting # routing/network analysis on top of postgic
          pgvector # vector embedding
          pgsodium
          wal2json # emit row changes as json
          omnigres
          pg-semver
          pg_uuidv7
          pg_partman # table partition management
          pgsql-http # synchronous http request/response client
          pointcloud # point cloud/LiDAR data
          # pg_graphql # FIXME: pg_graphql-1.5.12-unstable-2025-09-01 marked as broken
          # sqlite_fdw # FIXME: sqlite_fdw-2.5.0 marked as broken
          pg_rational # extract fraction arithmetic
          pg_relusage # trace relations traversed by statement
          timescaledb
          system_stats
          pg_hint_plan # influence planner choices with SQL hints in comments
          pg_byteamagic # auto-identify bytea blob file types
          pg_background
          plpgsql_check # linter
          jsonb_deep_sum # sum deeply nested numeric values
          # pg_auto_failover # FIXME: pg_auto_failover-2.2 marked as broken
          # timescaledb_toolkit # FIXME: timescaledb_toolkit-1.21.0 marked as broken
        ];

      hbaConf = ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD

        # "local" is for Unix domain socket connections only
        local   all             all                                     trust
        # IPv4 local connections:
        host    all             all             127.0.0.1/32            trust
        # IPv6 local connections:
        host    all             all             ::1/128                 trust
        # Allow replication connections from localhost, by a user with the
        # replication privilege.
        local   replication     all                                     trust
        host    replication     all             127.0.0.1/32            trust
        host    replication     all             ::1/128                 trust
        # FIXME: LAN connections
        host    ${config.name}  mfarabi         100.86.57.35/32         trust
      '';
    };
  };
}
