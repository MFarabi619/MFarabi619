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
    gaming.enable = true;
    nix.enable = true;
    audio.enable = true;
    network.enable = true;
    hardware.enable = true;
    system.enable = true;
    boot = {
      enable = true;
      useSystemdBoot = true;
      grubTheme = pkgs.hydenix.grub-retroboot; # or pkgs.hydenix.grub-pochita
      grubExtraConfig = "";                    # additional GRUB configuration
      kernelPackages = pkgs.linuxPackages_zen;
    };
    sddm = {
      enable = true;
      theme = pkgs.hydenix.sddm-candy;
    };
  };

  users.users.mfarabi = {
    isNormalUser = true;
    initialPassword = "mfarabi";
    extraGroups = [
      "wheel"          # sudo
      "networkmanager" # network management
      "video"          # display/graphics
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      # ==========  Doom Emacs ===========
      clang
      cmake         # vterm compilation and more
      coreutils
      binutils      # native-comp needs 'as', provided by this
      gnutls        # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      openscad
      openscad-lsp
      vips          # dired image previews
      imagemagick   # for image-dired
      tuntox        # collab
      sqlite        # :tools lookup & :lang org +roam
      ispell        # spelling
      nil           # nix lang formatting
      shellcheck    # shell script formatting
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
      kmon
      ugm
      lazyjournal
      lazysql
      # playwright
      # playwright-test
      pik
      netscanner
      systemctl-tui
      virt-viewer
    ];
  };

  programs = {
    npm.enable = true;
    virt-manager.enable = true;
  };

  services = {
    udev.extraHwdb = ''
          evdev:atkbd:*
            KEYBOARD_KEY_3a=leftctrl
        '';
    ttyd = {
      enable = true;
      writeable = true;
      port = 7681;
    };
    github-runners = {
      nixos = {
        enable = true;
        nodeRuntimes = "node22";
        url = "https://github.com/mira-amm/mira-amm-web";
        tokenFile = ./.runner.token;
      };
    };
  };

  virtualisation = {
    libvirtd.enable = true;
    docker = { # only enable either docker or podman -- Not both
      enable = true;
      autoPrune.enable = true;
    };
    podman.enable = false;
  };

  system.stateVersion = "25.05";
}
