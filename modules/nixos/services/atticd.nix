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
      require-proof-of-possession = false;
      database.url = "postgresql:///${config.services.atticd.user}?host=/run/postgresql";
    };
  };
}
