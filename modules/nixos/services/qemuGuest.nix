{
  config,
  ...
}:
{
  services.qemuGuest.enable = config.networking.hostName == "nixos-qemu";
}
