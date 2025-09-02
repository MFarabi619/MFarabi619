{
  services.xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };

      videoDrivers = [
        "modesetting"
        "fbdev"
        "vesa"
      ];
    };
}
