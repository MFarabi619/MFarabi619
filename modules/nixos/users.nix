{
  lib,
  config,
  ...
}:
{
  users.users.mfarabi = {
    description = "Mumtahin Farabi";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKz3Y58uXWAd7qPUfm+pcEPfCw484gt9Agjl+0hmZuU3 mfarabi@macos"
    ];

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
