{
  config,
  lib,
  ...
}:
{
  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        # BASE_URL = "mfarabi.sh";
        EXERCISM_API_URL = "https://api.exercism.org/v1";
      };
    };
}
