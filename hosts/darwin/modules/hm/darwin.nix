{
  targets = {
    darwin = {
      linkApps = {
        enable = true;
      };
      search = "Google";
      currentHostDefaults = {
        "com.apple.controlcenter" = {
          BatteryShowPercentage = true;
        };
      };
      defaults = {
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        NSGlobalDomain = {
          AppleMetricUnits = true;
          AppleMesurementUnits = "Centimeters";
        };
        "com.apple.finder" = {
          AppleShowAllFiles = true;
          showPathBar = true;
          ShowStatusBar = true;
        };
        "com.apple.dock" = {
          autohide = true;
          tileSize = 48;
          orientation = "bottom";
        };
        "com.apple.menuextra.clock" = {
          IsAnalog = true;
          ShowAMPM = true;
          ShowDate = 1;
        };
      };
      #      keybindings = {
      # "^u" = "deleteToBeginningOfLine:";
      #  "^w" = "deleteWordBackward:";
      #      };
    };
  };
}
