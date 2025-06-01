{
  inputs,
  ...
}:

let
  pkgs = import inputs.hydenix.inputs.hydenix-nixpkgs {
    inherit (inputs.hydenix.lib) system;
    config.allowUnfree = true;
    overlays = [
      inputs.hydenix.lib.overlays
      (final: prev: {
        userPkgs = import inputs.nixpkgs {
          config.allowUnfree = true;
        };
      })
    ];
  };
in
{
  nixpkgs.pkgs = pkgs;

  imports = [
    inputs.hydenix.inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.lib.nixOsModules
    ./hardware-configuration.nix
    ./modules/system

    # === GPU ===
      /*
      Leveraging `nixos-hardware` for drivers.
      Most common drivers are below. See more options: https://github.com/NixOS/nixos-hardware
      */
      # inputs.hydenix.inputs.nixos-hardware.nixosModules.common-gpu-nvidia # NVIDIA setups
      # inputs.hydenix.inputs.nixos-hardware.nixosModules.common-gpu-amd # AMD setups

      # === CPU ===
        # inputs.hydenix.inputs.nixos-hardware.nixosModules.common-cpu-amd # AMD
        inputs.hydenix.inputs.nixos-hardware.nixosModules.common-cpu-intel # Intel

        # === Other common modules ===
          inputs.hydenix.inputs.nixos-hardware.nixosModules.common-pc
          inputs.hydenix.inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  # nix.settings.trusted-users = [ "root" "mfarabi" ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
    };

    users."mfarabi" =
      { ... }:
      {
        imports = [
          inputs.hydenix.lib.homeModules
          inputs.nix-index-database.hmModules.nix-index # Nix-index-database - for comma and command-not-found
          inputs.nix-doom-emacs-unstraightened.homeModule
          ./modules/hm
        ];
      };
  };

  hydenix = {
    enable = true;
    hostname = "nixos";
    timezone = "America/Toronto";
    locale = "en_CA.UTF-8";
    # Optionally edit the below values, or leave to use hydenix defaults
    # visit ./modules/hm/default.nix for more options
    audio.enable = true;
    boot = {
      enable = true;
      useSystemdBoot = true;
      grubTheme = pkgs.hydenix.grub-retroboot; # or pkgs.hydenix.grub-pochita
      grubExtraConfig = ""; # additional GRUB configuration
      kernelPackages = pkgs.linuxPackages_zen; # default
    };
    gaming.enable = true;
    hardware.enable = true;
    network.enable = true;
    nix.enable = true;
    sddm = {
      enable = true;
      theme = pkgs.hydenix.sddm-candy;
    };
    system.enable = true;
  };

  users.users.mfarabi = {
    isNormalUser = true;
    initialPassword = "mfarabi";
    extraGroups = [
      "wheel" # For sudo access
      "networkmanager" # For network management
      "video" # For display/graphics access
      # Add other groups as needed
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      # ==========  Doom Emacs ===========
      nil
      cmake
      binutils      # native-comp needs 'as', provided by this
      gnutls        # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      vips          # dired image previews
      imagemagick   # for image-dired
      coreutils
      clang
      shellcheck
      tuntox        # collab
      sqlite        # :tools lookup & :lang org +roam
      # texlive     # :lang latex & :lang org (latex previews)
      # ============== 🤪 =================
      asciiquarium
      cowsay
      cmatrix
      figlet
      nyancat
      lolcat
      hollywood
      # ============= 🧑‍💻🐞‍ ================
      nix-inspect
      tgpt
      docker
      kmon
      ugm
      lazyjournal
      lazysql
      pik
      netscanner
      systemctl-tui
    ];
  };

  system.stateVersion = "25.05";
}
