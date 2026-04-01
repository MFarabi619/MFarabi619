{
  lib,
  config,
  ...
}:
let
  URLS = {
    BASE = "https://mfarabi.sh";
    EXERCISM = "https://api.exercism.org/v1";
  };
in
{
  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        PGUSER = "mfarabi";
        PGDATABASE = "postgres";
        PGPORT = config.services.postgres.port;
        PGHOST = config.services.postgres.listen_addresses;
      };
    };

  env = {
    BASE_URL = URLS.BASE;
    ZELLIJ_AUTO_EXIT = "true";
    ZELLIJ_AUTO_ATTACH = "true";
    # PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    # PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";
  };
}
