{
  services.xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };

      videoDrivers = [
        "vesa"
        "fbdev"
        "modesetting"
      ];
    };
}
