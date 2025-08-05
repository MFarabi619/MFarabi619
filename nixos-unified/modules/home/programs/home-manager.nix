{
  programs.home-manager = {
    enable = true;
  };

  services.home-manager = {
    autoExpire = {
      enable = true;
      frequency = "daily";
    };
    autoUpgrade = {
      enable = false;
      frequency = "daily";
    };
  };
}
