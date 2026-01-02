{
  services.tailscaleAuth = {
    enable = true;
    user = "tailscale-nginx-auth";
    group = "tailscale-nginx-auth";
    socketPath = "/run/tailscale-nginx-auth/tailscale-nginx-auth.sock";
  };
}
