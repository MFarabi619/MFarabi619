{
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    pam.services.swaylock = { };
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
}
