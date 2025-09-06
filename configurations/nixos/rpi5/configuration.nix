{ pkgs, ... }:
{
  system.stateVersion = "25.05";

  imports = [
    ../../../modules/nixos/common/services
    ../../../modules/nixos/gui
    ../../../modules/nixos/common/console.nix
    ../../../modules/nixos/common/environment.nix
    ../../../modules/nixos/common/fonts.nix
    ../../../modules/nixos/common/hardware.nix
    ../../../modules/nixos/common/i18n.nix
    ../../../modules/nixos/common/networking.nix
    ../../../modules/nixos/common/nix.nix
    ../../../modules/nixos/common/programs.nix
    ../../../modules/nixos/common/security.nix
    ../../../modules/nixos/common/systemd.nix
    ../../../modules/nixos/common/time.nix
    ../../../modules/nixos/common/virtualisation.nix
    ./hardware-configuration.nix
    ./services.nix
    ./systemd.nix
  ];

  # stylix = {
  #   enable = true;
  #   base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
  # };

  nix.settings = {
    trusted-users = [
      "mfarabi"
      "root"
      "nixos" # allow nix-copy to live system
    ];
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-linux";
  };

  networking = {
    # Use networkd instead of the pile of shell scripts
    # NOTE: SK: is it safe to combine with NetworkManager on desktops?
    useNetworkd = true;
    hostName = "rpi5";
  };

  users.users = {
    root.initialHashedPassword = "";
    mfarabi = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
      ];
      shell = pkgs.zsh;
      # allow graphical user to login without password
      initialHashedPassword = "";
      openssh = {
        authorizedKeys.keys = [
          # YOUR SSH PUB KEY HERE
        ];
      };
    };
  };
}
