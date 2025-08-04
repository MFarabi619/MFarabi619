{ config, pkgs, lib, ... }:
{
  # nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    hostName = "nixos-wsl";
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  time.timeZone = "America/Toronto";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
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
      substituters = [
      "https://hyprland.cachix.org"
      ];
      trusted-substituters = [
      "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
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
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        # "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
      ];
    };
  };

  wsl = {
    enable = true;
    defaultUser = "mfarabi";
    docker-desktop.enable = true;
    startMenuLaunchers = true;
    interop = {
      includePath = true;
    };
    # tarball.configPath = null;
    usbip = {
      enable = true;
      autoAttach = [ ];
    };
    useWindowsDriver = true;
    wslConf = {
      network = {
        generateHosts = true;
        generateResolvConf = true;
      };
      automount = {
        enabled = true;
        root = "/mnt";
      };
      boot = {
        systemd = true;
        command = "echo 'Hello from NixOS-WSL 👋";
      };
      interop = {
        enabled = true;
        appendWindowsPath = true;
      };
    };
  };

  environment = {
    systemPackages = with pkgs; [
      git
      lazygit
      wget
      vim
      neovim
      fastfetch
      btop
      yazi
      zellij
      gh
    ];
  };

  # let
  #   pkgs = nixpkgs.legacyPackages.x86_64-linux;
  #   in
    programs = {
      nix-ld = {
        enable = true;
        # package = nixpkgs.pkgs.nix-ld-rs; # only for NixOS 24.05
      };
    };
  system.stateVersion = "24.11";
}
