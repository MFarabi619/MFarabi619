{
  config,
  ...
}:
{
  services.spice-webdavd.enable = config.networking.hostName == "nixos-qemu";
}
