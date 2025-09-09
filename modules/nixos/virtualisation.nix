{
  virtualisation = {
    lxc.enable = false;
    lxd.enable = false;
    # useEFIBoot = false;
    # useSecureBoot = false;
    # graphics = true;
    # useDefaultFileSystems = true;
    # tpmr.enable = false;;

    libvirtd = {
      enable = true;
      startDelay = 0;
      sshProxy = true;
      onBoot = "ignore";
      parallelShutdown = 0;
      shutdownTimeout = 300;
      allowedBridges = [
       "virbr0"
      ];
      qemu = {
        runAsRoot = true;
        ovmf.enable = true;
        swtpm.enable = true;
      };
    };

    docker = {
      # only enable either docker or podman -- Not both
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        persistent = true;
        flags = [
          "--all"
        ];
      };
      rootless = {
        enable = false;
      };
      extraOptions = '''';
    };

    podman = {
      enable = false;
      dockerCompat = true;
      dockerSocket.enable = true;
    };
  };
}
