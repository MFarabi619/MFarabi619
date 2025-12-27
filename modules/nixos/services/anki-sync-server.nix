{
  config,
  ...
}:
{
  services.anki-sync-server = {
    enable = config.networking.hostName == "framework-desktop";

    baseDirectory = "%S/%N";

    users = [
      {
        username = "mfarabi619@gmail.com";
        passwordFile = "/var/lib/secrets/anki-sync-server";
      }
    ];
  };
}
