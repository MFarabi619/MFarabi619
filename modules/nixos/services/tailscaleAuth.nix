{
  config,
  ...
}:
{
  services.tailscaleAuth.enable = config.services.tailscale.enable;
}
