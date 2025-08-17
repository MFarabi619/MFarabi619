{
  wsl = {
    enable = true;
    defaultUser = "mfarabi";
    docker-desktop.enable = true;
    startMenuLaunchers = true;
    interop = {
      includePath = true;
    };
    # tarball.configPath = null;
    usbip = {
      enable = true;
      autoAttach = [ ];
    };
    useWindowsDriver = true;
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
