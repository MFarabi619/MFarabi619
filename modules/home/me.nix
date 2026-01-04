# User configuration module
{
  config,
  lib,
  ...
}:
{
  options = {
    me = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "mfarabi";
        description = "Your username as shown by `id -un`";
      };

      fullname = lib.mkOption {
        type = lib.types.str;
        default = "Mumtahin Farabi";
        description = "Your full name for use in Git config";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "mfarabi619@gmail.com";
        description = "Your email for use in Git config";
      };
    };
  };

  config = {
    home.username = config.me.username;
  };
}
