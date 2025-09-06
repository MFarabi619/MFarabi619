{
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
    polkit.enable = true;
    pam.services.swaylock = { };
    rtkit.enable = true;
  };
}
