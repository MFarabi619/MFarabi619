{
  pkgs,
  ...
}:
let
  probe-rs-tools = pkgs.probe-rs-tools.overrideAttrs (old: {
    cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "remote" ];
  });
in
{
  environment.systemPackages = [ probe-rs-tools ];
  services.udev = {
    enable = true;

    packages = with pkgs; [
      openocd
      probe-rs-tools
      platformio-core.udev
    ];

    extraHwdb = ''
      evdev:atkbd:*
      KEYBOARD_KEY_3a=leftctrl
    '';
  };
}
