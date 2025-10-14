{ config, pkgs, lib, ... }:

{
  hardware.raspberry-pi.config = {
    all = { # [all] conditional filter, https://www.raspberrypi.com/documentation/computers/config_txt.html#conditional-filters

      base-dt-params = {
        i2c = {
          enable = true;
          value = "on";
        };
      };

      # dt-overlays = {
      #   i2c-rtc = { 
      #     enable = true;
      #     params = {
      #       ds3231 = {
      #         enable = true;
      #         # value = "";
      #       };
      #     };
      #   };
      # };

    };
  };
}