{
  pkgs,
  ...
}:
{
  services.udev = {
    enable = true;

    packages = with pkgs; [
      platformio-core.udev
      openocd
    ];

    extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';
    };
}
