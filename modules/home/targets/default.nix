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
        directory = "Applications";
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
          AppleMeasurementUnits = "Centimeters";
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
        "^x" = "cut:";
        "^z" = "undo:";
        "^y" = "redo:";
        "^c" = "copy:";
        "@a" = "noop:";
        "^v" = "paste:";
        "^a" = "selectAll:";
        "^\010" = "deleteWordBackward:";
        # "^u" = "deleteToBeginningOfLine:";
      };
    };
  };
}
