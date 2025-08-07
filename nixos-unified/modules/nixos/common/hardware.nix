{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  hardware = {
    enableRedistributableFirmware = true;
    enableAllFirmware = true;
    graphics.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
