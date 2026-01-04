{
  flake,
  ...
}:
{
  imports = [
    flake.inputs.nixos-wsl.nixosModules.default
  ];

  hardware.uinput.enable = true;

  services = {
    seatd.enable = true;
    qemuGuest.enable = true;
    spice-webdavd.enable = true;
    spice-vdagentd.enable = true;
  };

  wsl = {
    enable = true;
    defaultUser = "mfarabi";
    useWindowsDriver = true;
    startMenuLaunchers = true;
    docker-desktop.enable = true;

    interop = {
      includePath = true;
    };
    # tarball.configPath = null;
    usbip = {
      enable = true;
      autoAttach = [ ];
    };

    wslConf = {
      network = {
        generateHosts = true;
        generateResolvConf = true;
      };

      automount = {
        enabled = true;
        root = "/mnt";
      };

      boot = {
        systemd = true;
        command = "echo 'Hello from NixOS-WSL 👋";
      };

      interop = {
        enabled = true;
        appendWindowsPath = true;
      };
    };
  };
}
