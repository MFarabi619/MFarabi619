{
  inputs,
  ...
}:
let
  # Package configuration - sets up package system with proper overlays
  # Most users won't need to modify this section
  pkgs = import inputs.hydenix.inputs.hydenix-nixpkgs {
    inherit (inputs.hydenix.lib) system;
    config.allowUnfree = true;
    overlays = [
      inputs.hydenix.lib.overlays
      (final: prev: {
        userPkgs = import inputs.nixpkgs {
          inherit (pkgs) system;
          config.allowUnfree = true;
        };
      })
    ];
  };
in
{
  nixpkgs.pkgs = pkgs; # Set pkgs for hydenix globally

  imports = [
    # hydenix inputs - Required modules, don't modify unless you know what you're doing
    inputs.hydenix.inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.lib.nixOsModules

    ./modules/system # Your custom system modules
    ./hardware-configuration.nix # Auto-generated hardware config

    # Hardware Configuration - Uncomment lines that match your hardware
    # Run `lshw -short` or `lspci` to identify your hardware

    # GPU Configuration (choose one):
    # inputs.hydenix.inputs.nixos-hardware.nixosModules.common-gpu-nvidia # NVIDIA
    inputs.hydenix.inputs.nixos-hardware.nixosModules.common-gpu-amd # AMD

    # CPU Configuration (choose one):
    inputs.hydenix.inputs.nixos-hardware.nixosModules.common-cpu-amd # AMD CPUs
    # inputs.hydenix.inputs.nixos-hardware.nixosModules.common-cpu-intel # Intel CPUs

    # Additional Hardware Modules - Uncomment based on your system type:
    inputs.hydenix.inputs.nixos-hardware.nixosModules.common-hidpi # High-DPI displays
    inputs.hydenix.inputs.nixos-hardware.nixosModules.common-pc-laptop # Laptops
    inputs.hydenix.inputs.nixos-hardware.nixosModules.common-pc-ssd # SSD storage
  ];

  # If enabling NVIDIA, you will be prompted to configure hardware.nvidia
  # hardware.nvidia = {
  #   open = true; # For newer cards, you may want open drivers
  #   prime = { # For hybrid graphics (laptops), configure PRIME:
  #     amdBusId = "PCI:0:2:0"; # Run `lspci | grep VGA` to get correct bus IDs
  #     intelBusId = "PCI:0:2:0"; # if you have intel graphics
  #     nvidiaBusId = "PCI:1:0:0";
  #     offload.enable = false; # Or disable PRIME offloading if you don't care
  #   };
  # };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users."mfarabi" =
      { ... }:
      {
        imports = [
          inputs.hydenix.lib.homeModules
          inputs.nix-index-database.homeModules.nix-index
          # ../../../modules/home/programs/git.nix
          # ../../../modules/home/programs/lazygit.nix
          # ../../../modules/home/programs/neovim
          # ../../../modules/home/programs/yazi.nix
          # ../../../modules/home/programs/zellij.nix
          # ../../../modules/home/programs/ripgrep.nix
          # ../../../modules/home/programs/television.nix
          # ../../../modules/home/programs/nix-search-tv.nix
          # ../../../modules/home/packages.nix
        ];
      };
  };

  users.users.mfarabi = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "docker"
      "networkmanager"
    ];
    shell = pkgs.zsh;
  };

  hydenix = {
    enable = true;
    hostname = "nixos";
    locale = "en_CA.UTF-8";
    timezone = "America/Toronto";

    audio.enable = true;
    boot = {
    enable = true;
    useSystemdBoot = false;
    grubTheme = "Retroboot";
    # grubExtraConfig = '''';
    kernelPackages = pkgs.linuxPackages_zen;
    };

    gaming.enable = true;
    hardware.enable = true;
    network.enable = true;
    nix.enable = true;
    sddm = {
    enable = true;
    theme = "Candy";
  };
  system.enable = true;
#   hm = {
# };
  };

  system.stateVersion = "25.05";
}
