{ ... }:
{
  imports =
    with builtins;
    map (fn: ./${fn}) (filter (fn: fn != "default.nix") (attrNames (readDir ./.)));

  services = {
    dbus.enable = true;
    upower.enable = true;
    libinput.enable = true; # input handling
    fstrim.enable = true; # ssd optimizer
    gvfs.enable = true; # For trash-cli to work properly, mounting USB + more

    udev.extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';

    xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };

      videoDrivers = [
        "modesetting"
        "fbdev"
        "vesa"
      ];
    };
  };
}
