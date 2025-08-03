{
  imports = [
    ./myusers.nix
  ];

  programs = {
    zsh = {
      enable = true;
    };
  };

  security = {
    rtkit.enable = true;
  };

  services = {
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
      };
      pulse.enable = true;
      jack.enable = true;
    };
    openssh.enable = true;
    # cachix-watch-store = {
      #   enable = true;
      #   verbose = true;
      #   # host = "";
      #   cacheName = "charthouse-labs";
      #   # jobs = 12;
      #   # compressionLevel = 0;
      #   cachixTokenFile = ../../cachixTokenFile;
      #   # signingKeyFile = "";
      # };
      hercules-ci-agent = {
        enable = true;
        settings = {
          concurrentTasks = 4;
          #   baseDirectory = "";
          #   binaryCachesPath = "";
          #   clusterJoinTokenPath = "";
          #   labels = "";
          #   workDirectory = "";
          #   apiBaseUrl = "";
        };
      };
  };

  virtualisation = {
    libvirtd.enable = true;
    docker = {
      # only enable either docker or podman -- Not both
      enable = true;
      autoPrune.enable = true;
    };
    podman.enable = false;
  };
}
