{
  lib,
  config,
  ...
}:
{
  users.users.mfarabi = {
    description = "Mumtahin Farabi";

    extraGroups = [
      "wheel"
      "video"
    ]
    ++ lib.optionals config.networking.networkmanager.enable [
      "networkmanager"
    ]
    ++ lib.optionals config.virtualisation.libvirtd.enable [
      "libvirt"
      "libvirtd"
      "qemu-libvirtd"
    ]
    ++ lib.optionals config.virtualisation.docker.enable [
      "docker"
    ];
  };
}
