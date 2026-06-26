{
  config,
  ...
}:
{
  services.atticd = {
    enable = config.networking.hostName == "framework-desktop";
    environmentFile = "/var/lib/secrets/attic";
    settings = {
      listen = "[::]:7070";
    };
  };
}
