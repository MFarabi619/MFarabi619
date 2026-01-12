{
  lib,
  config,
  ...
}:
{
  users.users.mfarabi = {
    isNormalUser = true;
    description = "Mumtahin Farabi";

    extraGroups = [
      "wheel"
      "video"
    ]
    ++ lib.optionals config.virtualisation.docker.enable [
      "docker"
    ]
    ++ lib.optionals config.networking.networkmanager.enable [
      "networkmanager"
    ];
  };
}
