{
  # Configure macOS system
  # More examples => https://github.com/ryan4yin/nix-darwin-kickstarter/blob/main/rich-demo/modules/system.nix
  system = {
    stateVersion = 6;
    startup.chime = true;
    primaryUser = "mfarabi";

    defaults = {
      spaces.spans-displays = false;
      LaunchServices.LSQuarantine = false;
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

      # Customize settings that not supported by nix-darwin directly
      # see the source code of this project to get more undocumented options:
      #    https://github.com/rgcr/m-cli
      #
      # All custom entries can be found by running `defaults read` command.
      # or `defaults read xxx` to read a specific domain.
      CustomUserPreferences={
       "com.apple.AdLib" = {
          personalizedAdsMigrated = false;
          allowIdentifierForAdvertising = false;
          allowApplePersonalizedAdvertising = false;
         };
      };

      screencapture = {
        type = "png";
        include-date = true;
        target = "clipboard";
        disable-shadow = true;
        show-thumbnail = true;
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
          { app = "/Applications/Leader Key.app"; }
          { app = "/Applications/GarageBand.app"; }
          { app = "/Applications/Arduino IDE.app"; }
        ];
      };

      finder = {
        ShowPathbar = true;
        QuitMenuItem = true;
        ShowStatusBar = true;
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

        AppleShowAllExtensions = true;
      };

      WindowManager = {
        AutoHide = false;                         # Auto hide stage strip showing recent apps
        HideDesktop = true;
        GloballyEnabled = false;                  # Enable Stage Manager Stage Manager arranges your recent windows into a single strip for reduced clutter and quick access
        StandardHideWidgets = true;
        EnableTilingByEdgeDrag = true;            # Enable dragging windows to screen edges to tile them
        StageManagerHideWidgets = true;
        EnableTiledWindowMargins = true;          # Enable window margins when tiling windows.
        StandardHideDesktopIcons = true;
        AppWindowGroupingBehavior = true;         # Grouping strategy when showing windows from an application
        EnableTopTilingByEdgeDrag = true;         # Enable dragging windows to the menu bar to fill the screen.
        EnableTilingOptionAccelerator = true;     # Enable holding alt to tile windows.
        EnableStandardClickToShowDesktop = false; # false means “Only in Stage Manager” true means “Always”
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

      NSGlobalDomain = {
        _HIHideMenuBar = true;
        AppleFontSmoothing = 2;
        NSWindowResizeTime = 0.05;
        AppleInterfaceStyle = "Dark";
        AppleTemperatureUnit = "Celsius";
        NSWindowShouldDragOnGesture = true;
        NSDisableAutomaticTermination = true;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = false;
        NSAutomaticWindowAnimationsEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        AppleInterfaceStyleSwitchesAutomatically = false;


        "com.apple.springing.delay" = 0.0;
        "com.apple.springing.enabled" = false;

        "com.apple.trackpad.scaling" = 3.0;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.trackpadCornerClickBehavior" = 1;

        "com.apple.sound.beep.feedback" = 1;
        "com.apple.swipescrolldirection" = true;
      };

      controlcenter = {
        Sound = false;
        Display = false;
        AirDrop = false;
        Bluetooth = false;
        FocusModes = false;
        NowPlaying = false;
        BatteryShowPercentage = false;
      };

    };

    keyboard = {
      enableKeyMapping = true;
      swapLeftCtrlAndFn = false;
      remapCapsLockToControl = true;
      swapLeftCommandAndLeftAlt = false;
    };
  };
}
