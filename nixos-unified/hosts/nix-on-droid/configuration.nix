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
