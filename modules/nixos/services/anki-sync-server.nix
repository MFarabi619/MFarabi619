{
  config,
  ...
}:
{
  services.anki-sync-server = {
   enable = builtins.elem config.networking.hostName [
    "framework-desktop"
    "nixos-server"
  ];

   baseDirectory = "%S/%N";

   users = [{
      username = "mfarabi619@gmail.com";
      passwordFile = "/var/lib/secrets/anki-sync-server";
     }];
    };
  }
