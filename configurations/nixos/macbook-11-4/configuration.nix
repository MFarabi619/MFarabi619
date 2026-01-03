# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  ...
}:

{
  system.stateVersion = "25.05";
  networking.hostName = "nixos-intel";
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  users.users.mfarabi = {
    isNormalUser = true;
    description = "Mumtahin Farabi";
    extraGroups = [
      "wheel"
      "video"
      "docker"
      "networkmanager"
    ];
  };

  services = {
    kanata = {
      enable = false;
      keyboards = {
        qwerty = {
          # port = null;
          # extraArgs = [ ];

          configFile = ../../../../modules/darwin/kanata.kbd;
          # config = ''
          #   (defsrc
          #   esc   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12 pwr
          #   <     1    2    3    4    5    6    7    8    9    0    -    =    bspc
          #   tab   q    w    e    r    t    y    u    i    o    p    [    ]
          #   caps  a    s    d    f    g    h    j    k    l    ;    '    \    enter
          #   lsft  ` z    x    c    v    b    n    m    ,    .    /         rsft                 up
          #   fn lctl  lalt lmet                   spc                   rmet  ralt  rctl  left  down  right
          #   )
          # '';
        };
      };
    };
  };
}
