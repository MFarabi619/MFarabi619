{
  config,
  ...
}:
{
  services.cachix-watch-store = {
    enable = true;
    verbose = true;
    cacheName = "mfarabi";
    # compressionLevel = 0;
    cachixTokenFile = "/var/lib/secrets/cachix_token";
  };
}
