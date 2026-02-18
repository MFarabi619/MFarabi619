{
  config,
  ...
}:
{
  services.tailscale.funnel = {
    enable = true;
    target = "${toString config.services.prometheus.port}";
  };
}
