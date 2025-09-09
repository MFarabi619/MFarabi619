{ pkgs, ... }:
{

  environment.systemPackages = with pkgs; [
    # rpiboot
    i2c-tools
    # rpi-imager
    # raspberrypifw
    # device-tree_rpi
    # raspberrypi-utils
    # raspberrypi-eeprom
    # raspberrypikwirelessFirmware
  ];

  fileSystems = {
    "/" = {
      fsType = "ext4";
      options = [ "noatime" ];
      device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
    };

    "/boot/firmware" = {
      fsType = "vfat";
      device = "/dev/disk/by-uuid/2175-794E";
      options = [
        "noauto"
        "noatime"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };
}
