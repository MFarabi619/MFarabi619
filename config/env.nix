{
  lib,
  config,
  ...
}:
{
  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        BASE_URL = "mfarabi.sh";
        EXERCISM_API_URL = "https://api.exercism.org/v1";
        # PGUSER = "mfarabi";
        # PGDATABASE = "postgres";
        # PGPORT = config.services.postgres.port;
        # PGHOST = config.services.postgres.listen_addresses;
      };
      # }
      # // lib.optionalAttrs config.microvisor.embassy.enable {
      #   ci.module.microvisor.embassy."probe-rs".server.address = "0.0.0.0";
      #   hostname.rpi5-16.extends = [ "ci" ];
      #   hostname.framework-desktop.extends = [ "ci" ];
    };

  env = {
    ZELLIJ_AUTO_EXIT = "true";
    ZELLIJ_AUTO_ATTACH = "true";
    # PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    # PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";
  };
}
