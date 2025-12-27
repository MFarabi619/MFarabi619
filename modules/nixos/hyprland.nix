{
  pkgs,
  inputs,
  ...
}:

{
  programs = {
    xwayland.enable = true;
    hyprlock.enable = true;

    uwsm = {
      enable = true;
      # waylandCompositors = {
      #     prettyName = "Hyprland";
      #     comment = "Hyprland compositor managed by UWSM";
      #     binPath = "/run/current-system/sw/bin/hyprland";
      # };
    };

    hyprland = {
      enable = true;
      # package = inputs.hyprland.packages."${pkgs.system}".hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };

    dconf = {
      enable = true;
      # settings = {
      #   "org/virt-manager/virt-manager/connections" = {
      #     autoconnect = [ "qemu:///system" ];
      #     uris = [ "qemu:///system" ];
      #   };
      # };
    };

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  services = {
    # getty.autologinUser = "mfarabi";

    kmscon = {
      enable = true;
      hwRender = true;
      # autologinUser = "mfarabi";
      extraConfig = "font-size=14";
      extraOptions = "--term xterm-256color";
    };

    displayManager = {
      defaultSession = "hyprland-uwsm";

      sddm = {
        enable = true;
        enableHidpi = true;
        autoNumlock = false;
        # setupScript = "";
        # stopScript = "";
        # extraPackages = [];

        settings = {
          Autologin = {
            User = "mfarabi";
            minimumUid = 1000;
            Session = "hyprland-uwsm";
          };
        };

        wayland = {
          enable = true;
          compositor = "weston";
        };

        theme = "${
          pkgs.where-is-my-sddm-theme.override { variants = [ "qt5" ]; }
        }/share/sddm/themes/where_is_my_sddm_theme_qt5";
      };
    };
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    xdgOpenUsePortal = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
    ];

    configPackages = with pkgs; [
      xdg-desktop-portal
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
    ];
  };
}
