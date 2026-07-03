{
  config,
  lib,
  ...
}:
{
  services.postgresql = lib.mkIf config.services.atticd.enable {
    enable = true;
    ensureDatabases = [ config.services.atticd.user ];
    ensureUsers = [
      {
        name = config.services.atticd.user;
        ensureDBOwnership = true;
      }
    ];
  };
}
