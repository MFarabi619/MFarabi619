{
  # Configure macOS system
  # More examples => https://github.com/ryan4yin/nix-darwin-kickstarter/blob/main/rich-demo/modules/system.nix
  system = {
    stateVersion = 6;
    startup.chime = true;
    primaryUser = "mfarabi";

    defaults = {
      spaces.spans-displays = false;

      finder = {
        ShowPathbar = true;
        QuitMenuItem = true;
        CreateDesktop = true;
        NewWindowTarget = "Home";

        _FXSortFoldersFirst = true;
        FXPreferredViewStyle = "icnv";
        FXDefaultSearchScope = "SCcf";
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirstOnDesktop = true;
        FXEnableExtensionChangeWarning = false;

        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        ShowExternalHardDrivesOnDesktop = true;

        ShowStatusBar = true;
        AppleShowAllExtensions = true;
      };

      WindowManager = {
        AutoHide = false; # Auto hide stage strip showing recent apps.
        HideDesktop = false;
        GloballyEnabled = false; # Enable Stage Manager Stage Manager arranges your recent windows into a single strip for reduced clutter and quick access
        StandardHideWidgets = false;
        EnableTilingByEdgeDrag = true; # Enable dragging windows to screen edges to tile them
        StageManagerHideWidgets = false;
        EnableTiledWindowMargins = true; # Enable window margins when tiling windows.
        StandardHideDesktopIcons = false;
        AppWindowGroupingBehavior = true; # Grouping strategy when showing windows from an application
        EnableTopTilingByEdgeDrag = true; # Enable dragging windows to the menu bar to fill the screen.
        EnableTilingOptionAccelerator = true; # Enable holding alt to tile windows.
        EnableStandardClickToShowDesktop = false; # false means “Only in Stage Manager” true means “Always”
      };

      screencapture = {
        type = "png";
        target = "preview";
        include-date = true;
        disable-shadow = true;
        show-thumbnail = true;
      };

      loginwindow = {
        GuestEnabled = false;
        SleepDisabled = true;
        autoLoginUser = "mfarabi";
        DisableConsoleAccess = false;
      };

      # universalaccess = {
      #   reduceMotion = true;
      #   reduceTransparency = false;
      # };

      trackpad = {
        Clicking = true;
        Dragging = true;
        ActuationStrength = 0;
        FirstClickThreshold = 0;
        SecondClickThreshold = 0;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

      NSGlobalDomain = {
        AppleFontSmoothing = 2;
        AppleInterfaceStyle = "Dark";
        AppleTemperatureUnit = "Celsius";
        NSDisableAutomaticTermination = true;
        NSAutomaticWindowAnimationsEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        AppleInterfaceStyleSwitchesAutomatically = false;

        NSWindowResizeTime = 0.1;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = false;

        _HIHideMenuBar = true;
        NSWindowShouldDragOnGesture = true;

        "com.apple.springing.delay" = 0.0;
        "com.apple.springing.enabled" = false;

        "com.apple.trackpad.scaling" = 3.0;
        "com.apple.sound.beep.feedback" = 1;
        "com.apple.swipescrolldirection" = true;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
      };

      controlcenter = {
        Display = true;
        AirDrop = false;
        Bluetooth = true;
      };

      dock = {
        autohide = true;
        launchanim = false;
        mru-spaces = false;
        autohide-delay = 0.0;
        orientation = "right";
        autohide-time-modifier = 1.0;
        expose-animation-duration = 0.0;

        appswitcher-all-displays = false;

        persistent-apps = [
          { app = "/Applications/Vivaldi.app"; }
        ];
      };
    };

    keyboard = {
      enableKeyMapping = true;
      swapLeftCtrlAndFn = true;
      remapCapsLockToControl = true;
      swapLeftCommandAndLeftAlt = true;
    };
  };
}
