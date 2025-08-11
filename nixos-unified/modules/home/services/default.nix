{
  services = {
    home-manager = {
      autoExpire = {
        enable = true;
        frequency = "daily";
      };
      autoUpgrade = {
        enable = true;
        frequency = "daily";
      };
    };
    gpg-agent = {
      enable = true;
      enableExtraSocket = true;
      enableSshSupport = true;
    };
  };
}
