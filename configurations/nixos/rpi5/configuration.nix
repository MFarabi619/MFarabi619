{ pkgs, ... }:
{
  system.stateVersion = "25.05";

  imports = [
    ../../../modules/nixos/services
    ../../../modules/nixos/hyprland.nix
    ../../../modules/nixos/console.nix
    ../../../modules/nixos/environment.nix
    ../../../modules/nixos/fonts.nix
    ../../../modules/nixos/hardware.nix
    ../../../modules/nixos/i18n.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/nix.nix
    ../../../modules/nixos/programs.nix
    ../../../modules/nixos/security.nix
    ../../../modules/nixos/systemd.nix
    ../../../modules/nixos/time.nix
    ../../../modules/nixos/virtualisation.nix
    ./hardware-configuration-new.nix
    ./services.nix
    ./systemd.nix
  ];

  # stylix = {
  #   enable = true;
  #   base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
  # };

  nix.settings = {
    trusted-users = [
      "root"
      "nixos" # allow nix-copy to live system
      "mfarabi"
    ];
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-linux";
  };

  networking = {
    hostName = "rpi5";
    # Use networkd instead of the pile of shell scripts
    # NOTE: SK: is it safe to combine with NetworkManager on desktops?
    useNetworkd = true;
  };

  users.users = {
    root.initialHashedPassword = "";
    mfarabi = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "networkmanager"
      ];
      shell = pkgs.zsh;
      # allow graphical user to login without password
      initialHashedPassword = "";
      # openssh = {
      #   authorizedKeys.keys = [
      #     # YOUR SSH PUB KEY HERE
      #   ];
      # };
    };
  };
}
