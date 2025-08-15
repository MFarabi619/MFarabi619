{ pkgs, ... }:
{

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
  ];

  environment.systemPackages = with pkgs; [
    i2c-tools
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
    root.initialHashedPassword = "";
  };

  services = {
    # auto login at virtual console
    getty.autologinUser = "mfarabi";
    udev.extraRules = ''
      # Ignore partitions with "Required Partition" GPT partition attribute
      # On our RPis this is firmware (/boot/firmware) partition
      ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
    '';
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
