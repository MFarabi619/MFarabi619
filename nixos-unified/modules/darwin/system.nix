{
  # Configure macOS system
  # More examples => https://github.com/ryan4yin/nix-darwin-kickstarter/blob/main/rich-demo/modules/system.nix
  system = {
    primaryUser = "mfarabi";

    defaults = {
      spaces = {
        spans-displays = false;
      };

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

      loginwindow = {
        autoLoginUser = "mfarabi";
        SleepDisabled = true;
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
