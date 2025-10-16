{
  pkgs,
  ...
}:
{
  services.podman = {
    enable = false;
    enableTypeChecks = true;
    autoUpdate.enable = true;
  };
}
