{
  virtualisation = {
    # useSecureBoot = false;
    # useEFIBoot = false;
    # useDefaultFileSystems = true;
    # graphics = true;
    # tpm = {
    #   enable = false;
    # };
    libvirtd = {
      enable = true;
      qemu = {
        ovmf = {
          enable = true;
        };
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
