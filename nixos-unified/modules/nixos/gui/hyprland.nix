{pkgs, inputs, ...}:

{

  programs = {
    uwsm.enable = true;
    hyprland = {
      enable = true;
      # package = inputs.hyprland.packages."${pkgs.system}".hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };
    hyprlock = {
      enable = true;
    };
  };

  environment = {
    systemPackages = with pkgs; [
      kitty
    ];
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };

  xdg = {
    # enable = true;
    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];

      xdgOpenUsePortal = true;

      configPackages = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];
    };
    # mimeApps.enable = true;

    # userDirs = {
      #   enable = true;
      #   createDirectories = true;
      # };
  };

  hardware = {
    graphics.enable = true;
  };

  services = {
    # xserver.enable = true;
    # hyprlock.enable = true;
  };
}
