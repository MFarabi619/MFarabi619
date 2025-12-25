{
  config,
  ...
}:
{
  services.anki-sync-server = {
   enable = config.networking.hostName == "framework-desktop" || config.networking.hostName == "nixos-server";
   port = 27701;
   address = "::1";
   openFirewall = false;
   baseDirectory = "%S/%N";

   users = [{
      username = "mfarabi619@gmail.com";
      passwordFile = "/var/lib/secrets/anki-sync-server";
     }];
    };
  }
