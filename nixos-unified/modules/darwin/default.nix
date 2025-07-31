# This is your nix-darwin configuration.
# For home configuration, see /modules/home/*
{inputs, pkgs, ...}:
{
  imports = [
    ./common
  ];

  environment = {
    pathsToLink = [
      "/share/zsh"
      "/share/bash-completion"
    ];
  };

  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
  };

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };

  nix = {
    linux-builder = {
      enable = false;
      workingDirectory = "var/lib/linux-builder";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      supportedFeatures = [
        "kvm"
        "benchmark"
        "big-parallel"
      ];
    };
    channel.enable = true;
    gc = {
      automatic = true;
    };
    optimise = {
      automatic = true;
    };
    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "mfarabi"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  power = {
    restartAfterFreeze = true;
    # restartAfterPowerFailure = true;
    sleep = {
      allowSleepByPowerButton = true;
      computer = "never";
      display = "never";
      # harddisk = "never";
    };
  };

  services = {
    #     github-runners = {
    #       macos = {
    #         enable = true;
    #         nodeRuntimes = "node22";
    #         url = "https://github.com/mira-amm/mira-amm-web";
    #         tokenFile = ./.runner.token;
    #         ephemeral = false;
    #         extraLabels = ["macbook-air"];
    #       };
    #     };
    openssh = {
      enable = true;
    };
  };

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };

  # Configure macOS system
  # More examples => https://github.com/ryan4yin/nix-darwin-kickstarter/blob/main/rich-demo/modules/system.nix

  system = {
    defaults = {
      finder = {
        AppleShowAllExtensions = true;
        FXEnableExtensionChangeWarning = false;
        _FXShowPosixPathInTitle = true;
        QuitMenuItem = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowStatusBar = true;
        # ShowPathBar = true;
        _FXSortFoldersFirst = true;
        _FXSortFoldersFirstOnDesktop = true;
      };
      screencapture = {
        disable-shadow = true;
        include-date = true;
        show-thumbnail = true;
        target = "preview";
        type = "png";
      };
      # universalaccess = {
      #   reduceMotion = true;
      #   reduceTransparency = false;
      # };

      trackpad = {
        ActuationStrength = 0;
        Clicking = true;
        Dragging = true;
        FirstClickThreshold = 0;
        SecondClickThreshold = 0;
        TrackpadThreeFingerDrag = true;
        TrackpadRightClick = true;
      };

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

      NSGlobalDomain = {
        AppleFontSmoothing = 2;
        AppleInterfaceStyle = "Dark";
        AppleInterfaceStyleSwitchesAutomatically = false;
        AppleTemperatureUnit = "Celsius";
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false;
        NSDisableAutomaticTermination = false;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSWindowShouldDragOnGesture = true;
        "com.apple.swipescrolldirection" = true;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
        "com.apple.trackpad.scaling" = 3.0;
        "com.apple.sound.beep.feedback" = 1;

      };

      controlcenter = {
        AirDrop = false;
        Bluetooth = true;
        Display = true;
      };

      dock = {
        launchanim = false;
        expose-animation-duration = 0.0;
        mru-spaces = false;
        persistent-apps = [
          { app = "/Applications/Vivaldi.app"; }
        ];
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

    startup.chime = true;
    stateVersion = 6;
  };
}
