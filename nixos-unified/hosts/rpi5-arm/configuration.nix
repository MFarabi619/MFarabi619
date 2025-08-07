{ pkgs, lib, ... }:
{
  imports = [
    ../../modules/nixos/gui
  ];

  # stylix = {
  #   enable = true;
  #   base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
  # };

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };

  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u16n.psf.gz";

    # Make colored console output more readable
    # for example, `ip addr`s (blues are too dark by default)
    # Tango theme: https://yayachiken.net/en/posts/tango-colors-in-terminal/
    colors = [
      "000000"
      "CC0000"
      "4E9A06"
      "C4A000"
      "3465A4"
      "75507B"
      "06989A"
      "D3D7CF"
      "555753"
      "EF2929"
      "8AE234"
      "FCE94F"
      "739FCF"
      "AD7FA8"
      "34E2E2"
      "EEEEEC"
    ];
  };

  networking = {
    # Use networkd instead of the pile of shell scripts
    # NOTE: SK: is it safe to combine with NetworkManager on desktops?
    useNetworkd = true;
    hostName = "rpi5";
    networkmanager.enable = true;
    firewall = {
      # Keep dmesg/journalctl -k output readable by NOT logging
      # each refused connection on the open internet.
      logRefusedConnections = false;
      enable = true;
      allowedTCPPorts = [
        # SSH
        22
      ];
      allowedUDPPorts = [
        # DHCP
        68
        546
      ];
    };
  };

  time.timeZone = "America/Toronto";

  users.users = {
    mfarabi = {
      initialPassword = "passwd";
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
      ];
      shell = pkgs.zsh;
    };
    root.initialHashedPassword = "";
  };

  programs = {
    zsh.enable = true;
  };

  environment = {
    systemPackages = with pkgs; [
      brightnessctl # screen brightness control
      udiskie # manage removable media
      ntfs3g # ntfs support
      exfat # exFAT support
      libinput-gestures # actions touchpad gestures using libinput
      libinput # libinput library
      lm_sensors # system sensors
      pciutils # pci utils
      # ========== Stylix ===========
      dconf # configuration storage system
      dconf-editor # dconf editor
      zsh-powerlevel10k
      meslo-lgs-nf
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
    };
    pathsToLink = [
      "/share/zsh"
      "/share/bash-completion"
      "/share/icons"
      "/share/themes"
      "/share/fonts"
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];
  };

  security = {
    polkit.enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };
    udev.extraRules = ''
      # Ignore partitions with "Required Partition" GPT partition attribute
      # On our RPis this is firmware (/boot/firmware) partition
      ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
    '';
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      max-jobs = "auto";

      trusted-users = [
        "root"
        "mfarabi"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://cache.lix.systems"
        "https://nix-darwin.cachix.org"
        "https://mfarabi.cachix.org"
        "https://cachix.cachix.org"
        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"
      ];

      trusted-substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://cache.lix.systems"
        "https://nix-darwin.cachix.org"
        "https://mfarabi.cachix.org"
        "https://cachix.cachix.org"
        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
        "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
      ];

      extra-substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.lix.systems"
        "https://devenv.cachix.org"
        # "https://fuellabs.cachix.org"
      ];

      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        # "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
      ];
    };

    channel.enable = true;
    gc.automatic = true;
    optimise.automatic = true;
  };

  systemd = {
    network.wait-online.enable = false;
    services = {
      # The notion of "online" is a broken concept
      # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
      # https://github.com/NixOS/nixpkgs/issues/247608
      NetworkManager-wait-online.enable = false;
      # Do not take down the network for too long when upgrading,
      # This also prevents failures of services that are restarted instead of stopped.
      # It will use `systemctl restart` rather than stopping it with `systemctl stop`
      # followed by a delayed `systemctl start`.
      systemd-networkd.stopIfChanged = false;
      # Services that are only restarted might be not able to resolve when resolved is stopped before
      systemd-resolved.stopIfChanged = false;
    };
  };

  system.stateVersion = "25.05";
}
