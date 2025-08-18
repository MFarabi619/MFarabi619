{
  pkgs,
  lib,
  ...
}:
{
  targets = {
    darwin = lib.mkIf pkgs.stdenv.isDarwin {
      search = "Google";
      linkApps = {
        enable = true;
        directory = "Applications/Nix Apps";
      };
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
      # https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html
      keybindings = {
        "^u" = "deleteToBeginningOfLine:";
        "^w" = "deleteWordBackward:";
      };
    };
  };
}
