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

        inherit (inputs.playwright-web-flake.packages.${inputs.hydenix.lib.system})
          playwright-test
          playwright-driver
          ;
      })
    ];
  };
in
{
  nixpkgs.pkgs = pkgs;
  system.stateVersion = "25.05";

  imports = [
    inputs.hydenix.inputs.home-manager.nixosModules.home-manager
    inputs.hydenix.lib.nixOsModules
    ./framework-16.nix
    ./system

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
      ];
      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

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
          ../modules/home
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
      grubExtraConfig = ""; # additional GRUB configuration
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
      "wheel" # sudo
      "networkmanager" # network management
      "video" # display/graphics
    ];
    shell = pkgs.zsh;
  };

  environment = {
    shellInit = ''
      export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
      export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    '';
  };

}
