{ pkgs, lib, ... }:
{
  # stylix = {
  #   enable = true;
  #   base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
  # };

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
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
      # ==========  Doom Emacs ===========
      # clang
      cmake # vterm compilation and more
      coreutils
      binutils # native-comp needs 'as', provided by this
      gnutls # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      openscad
      openscad-lsp
      vips # dired image previews
      imagemagick # for image-dired
      tuntox # collab
      sqlite # :tools lookup & :lang org +roam
      ispell # spelling
      nil # nix lang formatting
      shellcheck # shell script formatting
      # texlive     # :lang latex & :lang org (latex previews)
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
      # "/share/icons"
      # "/share/themes"
      # "/share/fonts"
      # "/share/xdg-desktop-portal"
      # "/share/applications"
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
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "mfarabi"
        "root"
      ];
      extra-substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    };
  };

  systemd = {
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
    network.wait-online.enable = false;
  };

  system.stateVersion = "25.05";
}
