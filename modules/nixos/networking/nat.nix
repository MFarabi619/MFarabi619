{
  networking.nat = {
    enable = false;
    externalInterface = "eth0";

    internalInterfaces = [
      "ve-+"
    ];
  };
}
