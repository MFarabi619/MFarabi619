{
  virtualisation = {
    lxc.enable = false;
    # useEFIBoot = false;
    # tpmr.enable = false;
    # useSecureBoot = false;
    # useDefaultFileSystems = true;

    libvirtd = {
      enable = true;
      onBoot = "ignore";
      qemu = {
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    # only enable either docker or podman -- Not both
    docker = {
      enable = true;

      autoPrune = {
        enable = true;
        persistent = true;
        flags = [
          "--all"
        ];
      };
    };

    podman = {
      enable = false;
      dockerCompat = true;
      dockerSocket.enable = true;
    };
  };
}
