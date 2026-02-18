{
  pkgs,
  ...
}:
{
  services.postgres = {
    port = 54322;
    enable = false;
    listen_addresses = "*";
    # hbaConf = "pg_hba.conf";
    package = pkgs.postgresql_17;

    initialDatabases = [
      {
        name = "postgres";
        user = "postgres";
        pass = "postgres";
      }
    ];

    settings = {
      max_wal_size = "1GB";
      min_wal_size = "80MB";
      datestyle = "iso, mdy";
      lc_time = "en_US.UTF-8";
      shared_buffers = "128MB";
      lc_numeric = "en_US.UTF-8";
      lc_messages = "en_US.UTF-8";
      lc_monetary = "en_US.UTF-8";
      dynamic_shared_memory_type = "posix";
      default_text_search_config = "pg_catalog.english";
    };

    extensions =
      extensions: with extensions; [
        pgvector
        pgsodium
        plpgsql_check
        # pgvectorscale
      ];
  };
}
