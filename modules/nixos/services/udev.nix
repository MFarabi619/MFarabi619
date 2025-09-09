{
  services.udev = {
    enable = true;
    extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';
    };
}
