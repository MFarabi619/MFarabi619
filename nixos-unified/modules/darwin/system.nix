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
        CreateDesktop = true;
        ShowPathbar = true;
        QuitMenuItem = true;
        NewWindowTarget = "Home";

        _FXSortFoldersFirst = true;
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirstOnDesktop = true;
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "icnv";
        FXDefaultSearchScope = "SCcf";

        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        ShowExternalHardDrivesOnDesktop = true;

        ShowStatusBar = true;
        AppleShowAllExtensions = true;
      };

      WindowManager = {
        GloballyEnabled = false; # Enable Stage Manager Stage Manager arranges your recent windows into a single strip for reduced clutter and quick access
        HideDesktop = false;
        StageManagerHideWidgets = false;
        StandardHideDesktopIcons = false;
        StandardHideWidgets = false;
        EnableStandardClickToShowDesktop = false; # false means “Only in Stage Manager” true means “Always”
        AppWindowGroupingBehavior = true; # Grouping strategy when showing windows from an application
        AutoHide = false; # Auto hide stage strip showing recent apps.
        EnableTiledWindowMargins = true; # Enable window margins when tiling windows.
        EnableTilingByEdgeDrag = true; # Enable dragging windows to screen edges to tile them
        EnableTilingOptionAccelerator = true; # Enable holding alt to tile windows.
        EnableTopTilingByEdgeDrag = true; # Enable dragging windows to the menu bar to fill the screen.
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
        DisableConsoleAccess = false;
        GuestEnabled = false;
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
        AppleTemperatureUnit = "Celsius";
        AppleInterfaceStyleSwitchesAutomatically = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false;
        NSDisableAutomaticTermination = true;

        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = false;
        NSWindowResizeTime = 0.1;

        NSWindowShouldDragOnGesture = true;

        _HIHideMenuBar = true;

        "com.apple.springing.enabled" = false;
        "com.apple.springing.delay" = 0.0;

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
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 1.0;
        launchanim = false;
        expose-animation-duration = 0.0;
        mru-spaces = false;
        orientation = "right";

        appswitcher-all-displays = false;

        persistent-apps = [
          { app = "/Applications/Vivaldi.app"; }
        ];
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
      swapLeftCommandAndLeftAlt = true;
      swapLeftCtrlAndFn = true;
    };

    startup.chime = true;
    stateVersion = 6;
  };
}
