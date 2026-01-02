{
  config,
  ...
}:
{
  services.tailscaleAuth = {
    enable = config.services.tailscale.enable;
    user = "tailscale-nginx-auth";
    group = "tailscale-nginx-auth";
    socketPath = "/run/tailscale-nginx-auth/tailscale-nginx-auth.sock";
  };
}
