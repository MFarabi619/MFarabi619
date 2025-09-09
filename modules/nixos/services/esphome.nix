{
  services.esphome = {
    enable = false;
    port = 6052;
    usePing = false;
    openFirewall = false;
    address = "localhost";
    enableUnixSocket = false;
    # allowedDevices = [
    #   "char-ttyS"
    #   "char-ttyUSB"
    # ];
  };
}
