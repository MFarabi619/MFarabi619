{
  config,
  lib,
  pkgs,
  ...
}:

let
  sshdTmpDirectory = "${config.user.home}/ssh-tmp";
  sshdDirectory = "${config.user.home}/sshd";
  pathToPubKey = "...";
  port = 8022;
in
{
  imports = [
    ../../modules/nixos/common/time.nix
  ];

  system.stateVersion = "24.05";

  build = {
    activation = {
      sshd = ''
        $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${config.user.home}/.ssh"
        $DRY_RUN_CMD cat ${pathToPubKey} > "${config.user.home}/.ssh/authorized_keys"

        if [[ ! -d "${sshdDirectory}" ]]; then
        $DRY_RUN_CMD rm $VERBOSE_ARG --recursive --force "${sshdTmpDirectory}"
        $DRY_RUN_CMD mkdir $VERBOSE_ARG --parents "${sshdTmpDirectory}"

        $VERBOSE_ECHO "Generating host keys..."
        $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f "${sshdTmpDirectory}/ssh_host_rsa_key" -N ""

        $VERBOSE_ECHO "Writing sshd_config..."
        $DRY_RUN_CMD echo -e "HostKey ${sshdDirectory}/ssh_host_rsa_key\nPort ${toString port}\n" > "${sshdTmpDirectory}/sshd_config"

        $DRY_RUN_CMD mv $VERBOSE_ARG "${sshdTmpDirectory}" "${sshdDirectory}"
        fi
      '';
    };
  };

  environment = {
    packages = with pkgs; [
      sudo
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

      (writeScriptBin "sshd-start" ''
        #!${runtimeShell}

        echo "Starting sshd in non-daemonized way on port ${toString port}"
        ${openssh}/bin/sshd -f "${sshdDirectory}/sshd_config" -D
      '')
    ];

    # Backup etc files instead of failing to activate generation if a file already exists in /etc
    etcBackupExtension = ".bak";

    sessionVariables = {
      EDITOR = "nvim";
    };
  };

  # user = {
  # userName = "mfarabi";
  # home = "";
  # shell = "/bin/zsh";
  # };

  nix = {
    settings = {
      auto-optimise-store = true;
      max-jobs = "auto";

      trusted-users = [
        "root"
        "mfarabi"
        "nix-on-droid"
      ];

      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://cache.lix.systems"
        "https://nix-darwin.cachix.org"
        "https://mfarabi.cachix.org"
        "https://cachix.cachix.org"
        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"
      ];

      trusted-substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
        "https://cache.lix.systems"
        "https://nix-darwin.cachix.org"
        "https://mfarabi.cachix.org"
        "https://cachix.cachix.org"
        "https://emacs-ci.cachix.org"
        "https://nixvim.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
        "mfarabi.cachix.org-1:FPO/Xsv7VIaZqGBAbjYMyjU1uUekdeEdMbWfxzf5wrM="
        "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
        "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4="
        "nixvim.cachix.org-1:8xrm/43sWNaE3sqFYil49+3wO5LqCbS4FHGhMCuPNNA="
      ];

      extra-substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.lix.systems"
        "https://devenv.cachix.org"
        # "https://fuellabs.cachix.org"
      ];

      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        # "fuellabs.cachix.org-1:3gOmll82VDbT7EggylzOVJ6dr0jgPVU/KMN6+Kf8qx8="
      ];
    };

    channel.enable = true;
    gc.automatic = true;
    optimise.automatic = true;
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

  terminal = {
    # colors = {
    #   };
    font = "${pkgs.terminus_font_ttf}/share/fonts/truetype/TerminusTTF.ttf";
  };

  # documentation = {
  #   enable = true;
  #   doc.enable = true;
  #   info.enable = true;
  #   man.enable = true;
  # };

  nix = {
    substituters = [
      "https://cache.nixos.org"
      "https://cache.lix.systems"
      "https://nix-community.cachix.org"
    ];
    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZP"
      "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbv"
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    extraOptions = ''
      experimental-features = nix-command flakes
      auto-optimise-store = true
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

  terminal = {
    # colors = {
    #   };
    font = "${pkgs.terminus_font_ttf}/share/fonts/truetype/TerminusTTF.ttf";
  };

  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };
}
