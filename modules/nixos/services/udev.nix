{
  pkgs,
  ...
}:
{
  services.udev = {
    enable = true;

    packages = with pkgs; [
      openocd
      platformio-core.udev
    ];

    extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';
  };
}
