{ pkgs, ... }:
{
  imports =
    with builtins;
    map (fn: ./${fn}) (filter (fn: fn != "default.nix") (attrNames (readDir ./.)));

  services = {
    dbus.enable = true;
    upower.enable = true;
    libinput.enable = true;
    gvfs.enable = true; # For trash-cli to work properly

    udev.extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';

    ttyd = {
      enable = false;
      port = 7681;
      entrypoint = (pkgs.zsh);
      writeable = true;
      terminalType = "xterm-kitty";
      checkOrigin = false;
      logLevel = 7;
      signal = 1;
      maxClients = 0;
      clientOptions = {
        fontSize = "16";
        fontFamily = "Fira Code";
      };
      # indexFile = "";
      # passwordFile = "";
    };

    github-runners = {
      nixos = {
        enable = false;
        nodeRuntimes = "node22";
        url = "https://github.com/MFarabi619/MFarabi619";
        # tokenFile = ./.runner.token;
      };
    };

    xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };

      videoDrivers = [
        "modesetting"
        "fbdev"
        "vesa"
      ];
    };

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

    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
      };
    };

    udisks2 = {
      enable = true;
      mountOnMedia = true;
    };

    cachix-watch-store = {
      enable = false;
      verbose = true;
      # host = "";
      cacheName = "mfarabi";
      # jobs = 12;
      # compressionLevel = 0;
      # cachixTokenFile = ../../cachixTokenFile;
      # signingKeyFile = "";
    };

    hercules-ci-agent = {
      enable = false;
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
    #  hydra-create-user mfarabi --full-name 'Mumtahin Farabi' --email-address 'mfarabi619@gmail.com' --password-prompt --role admin
    hydra = {
      enable = false;
      hydraURL = "http:/localhost:9870";
      notificationSender = "hydra@localhost";
      buildMachinesFiles = [ ];
      useSubstitutes = true;
      # logo = ./;
    };
  };
}
