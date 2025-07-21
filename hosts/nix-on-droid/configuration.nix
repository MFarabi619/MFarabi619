{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment = {
    packages = with pkgs; [
      vim
      neovim
      procps
      killall
      diffutils
      findutils
      utillinux
      tzdata
      hostname
      man
      gnugrep
      gnupg
      gnused
      gnutar
      bzip2
      gzip
      xz
      zip
      unzip
      git
      gh
      lazygit
      openssh
      zellij
      zsh
    ];

    # Backup etc files instead of failing to activate generation if a file already exists in /etc
    etcBackupExtension = ".bak";

    sessionVariables = {
     EDITOR = "nvim";
    };
  };

  system.stateVersion = "24.05";

  # user = {
  #   userName = "mfarabi";
  #   home = "";
  #   shell = "/bin/zsh"
  # };

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    };
    # github.com/nix-community/nix-on-droid/wiki
    # nix-community.github.io/nix-on-droid/nix-on-droid-options.html
    android-integration = {
     am.enable = true;
     termux-open.enable = true;
     termux-open-url.enable = true;
     termux-reload-settings.enable = true;
     termux-setup-storage.enable = true;
     termux-wake-lock.enable = true;
     xdg-open.enable = true;
    };

    # terminal = {
    #   colors = {
    #   };
    #   font = ""
    # };

  # documentation = {
  #   enable = true;
  #   doc.enable = true;
  #   info.enable = true;
  #   man.enable = true;
  # };

  time.timeZone = "America/Toronto";

  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };
}

