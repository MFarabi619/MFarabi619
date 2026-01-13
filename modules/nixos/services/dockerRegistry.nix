{
  config,
  ...
}:
{
  services.dockerRegistry = {
    enableGarbageCollect = true;
    enable = config.networking.hostName == "framework-desktop";
  };
}
