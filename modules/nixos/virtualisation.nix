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
      qemu.swtpm.enable = true;
    };

    oci-containers = {
      backend = "docker";

      containers = {
        # excalidraw = {
        #   pull = "missing"; # "always" | "missing" | "never" | "newer"
        #   autoStart = false;
        #   hostname = "excalidraw";
        #   workdir = "/var/lib/excalidraw";
        #   image = "excalidraw/excalidraw:latest";

        #   # cmd = [ ];
        #   ports = [
        #     "5000:80"
        #   ];
        # };
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
