{
  services.openssh = {
    enable = false;
    settings = {
      PermitRootLogin = "yes";
    };
  };
}
