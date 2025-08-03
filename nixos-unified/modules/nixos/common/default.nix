{
  imports = [
    ./myusers.nix
  ];

  hardware = {
    graphics.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  programs = {
    zsh = {
      enable = true;
    };
  };

  security = {
    polkit.enable = true;
    pam.services.swaylock = { };
    rtkit.enable = true;
  };

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  services = {
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
    };
    blueman.enable = true;
    dbus.enable = true;
    upower.enable = true;
    openssh.enable = true;
    libinput.enable = true;
    udisks2 = {
      enable = true;
      mountOnMedia = true;
    };
    # For trash-cli to work properly
    gvfs.enable = true;
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
      # https://nixos.wiki/wiki/Hydra
      #
      #  hydra-create-user mfarabi --full-name 'Mumtahin Farabi' --email-address 'mfarabi619@gmail.com' --password-prompt --role admin
      hydra = {
       enable = true;
       hydraURL = "http:/localhost:9870";
       notificationSender = "hydra@localhost";
       buildMachinesFiles = [];
       useSubstitutes = true;
       # logo = ./;
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
