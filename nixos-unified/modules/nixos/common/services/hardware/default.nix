{
  services.hardware = {
    bolt.enable = true;   # manage thunderbolt 3 security settings
    uinput.enable = true; # manage input emulations
    openrgb = {           # keyboard backlights
     enable = false;
     server.port = 6742;
    };
    usb-modeswitch.enable = true; # USB WLAN & WWAN adapters
  };
}
