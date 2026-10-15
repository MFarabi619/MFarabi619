{
  services.radicle-web.enable = false;
  services.radicle.node = {
    enable = false; # FIXME: marked insecure, hit on 1:49 PM, Oct 1, 2026
    lazy.enable = true;
    # environment = {};
  };
}
