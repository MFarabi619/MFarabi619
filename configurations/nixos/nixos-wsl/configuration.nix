{
  config,
  pkgs,
  lib,
  ...
}:
{
  system.stateVersion = "25.05";
  networking.hostName = "nixos-wsl";
  hardware.uinput.enable = true;

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
    # hostPlatform = lib.mkDefault "x86_64-linux";
  };

  services = {
    seatd = {
      enable = true;
      user = "root"; # default
      group = "seat"; # default
    };
    qemuGuest.enable = true;
    spice-vdagentd.enable = true;
    spice-webdavd.enable = true;
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
