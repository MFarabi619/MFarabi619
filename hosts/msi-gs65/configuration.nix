# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ 
    ./hardware-configuration.nix
    ];

    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
      kernelPackages = pkgs.linuxPackages_latest;
    };

    networking = {
      hostName = "nixos";
      networkmanager.enable = true;
      # wireless.enable = true; # enable wireless support via wpa_supplicant
      # proxy = {
      #  default = "http://user:password@proxy:port/";
      #  noProxy = "127.0.0.1,localhost,internal.domain";
      #  };
      # firewall = {
      #   enable = false;
      #   allowedTCPPorts = [ ... ];
      #   allowedUDPPorts = [ ... ];
      #  };
    };

    time.timeZone = "America/Toronto";
    i18n.defaultLocale = "en_CA.UTF-8";

    services = {
      openssh.enable = true;
      udev.extraHwdb = ''
        evdev:atkbd:*
        KEYBOARD_KEY_3a=leftctrl
      '';
      xserver.xkb = {
        layout = "us";
        variant = "";
      };
    };

    users.users.mfarabi = {
      isNormalUser = true;
      description = "Mumtahin Farabi";
      extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      ];
      packages = with pkgs; [
        neovim
      ];
    };

    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      vim
      wget
    ];

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
      #   enable = true;
      #   enableSSHSupport = true;
      # };

    system.stateVersion = "25.05";
}
