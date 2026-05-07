{
  config,
  ...
}:
{
  services.spice-vdagentd.enable = config.networking.hostName == "nixos";
}
