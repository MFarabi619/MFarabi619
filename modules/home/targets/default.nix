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
          DSDontWriteUSBStores = true;
          DSDontWriteNetworkStores = true;
        };

        NSGlobalDomain = {
          AppleMetricUnits = true;
          AppleMesurementUnits = "Centimeters";
        };

        "com.apple.finder" = {
          showPathBar = true;
          ShowStatusBar = true;
          AppleShowAllFiles = true;
        };

        "com.apple.dock" = {
          tileSize = 48;
          autohide = true;
          orientation = "bottom";
        };

        "com.apple.menuextra.clock" = {
          ShowDate = 1;
          IsAnalog = true;
          ShowAMPM = true;
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
