{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
      # ==========  Doom Emacs ===========
      # clang
      cmake         # vterm compilation and more
      coreutils
      binutils      # native-comp needs 'as', provided by this
      gnutls        # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      openscad
      openscad-lsp
      vips          # dired image previews
      imagemagick   # for image-dired
      tuntox        # collab
      sqlite        # :tools lookup & :lang org +roam
      ispell        # spelling
      nil           # nix lang formatting
      shellcheck    # shell script formatting
      # texlive     # :lang latex & :lang org (latex previews)
  ];

  users.users.mfarabi = {
    home = "/Users/mfarabi";
  };

  nix = {
    gc = {
     automatic = true;
    };
    optimise = {
     automatic = true;
    };
    settings = {
      trusted-users = [ "root" "mfarabi" ];
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  documentation = {
   doc.enable = true;
   info.enable = true;
   man.enable = true;
  };

  system = {
    primaryUser = "mfarabi";
    defaults = {
      universalaccess = {
        reduceMotion = true;
        reduceTransparency = false;
      };

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
        AppleTemperatureUnit = "Celsius";
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = true;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSWindowShouldDragOnGesture = true;
        "com.apple.swipescrolldirection" = true;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.scaling" = 3.0;
      };

      controlcenter = {
        Bluetooth = true;
        Display = true;
      };

      dock = {
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

    time.timeZone = "America/Toronto";

  networking = {
    computerName = "macos";
    hostName = "macos";
    localHostName = "macos";
    wakeOnLan.enable = true;
  };

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config = {
      allowUnfree = true;
    };
  };

  environment.pathsToLink = [
    "/share/zsh"
    "/share/bash-completion"
  ];
}
