{
  config,
  ...
}:
{
  services.dockerRegistry = {
    enable = config.networking.hostName == "framework-desktop";
    enableGarbageCollect = true;
  };
}
