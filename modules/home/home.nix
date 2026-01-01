{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./packages.nix
  ];

  home = {
    shell = {
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableShellIntegration = true;
    };

    shellAliases = {
      n = "nvim";
      cat = "bat";
      z = "zoxide";
      man = "batman";
      zlj = "zellij";
      lsh = "lazyssh";
      mkdir = "mkdir -p";
      # grep = "batgrep";
      # TODO: add batpipe
    }
    // lib.optionalAttrs (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) {
      stmcli = "/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI";
    };

    file = {
      "receipt.json" = {
        enable = false;
        source = ./receipt.json;
      };
    };

    sessionVariables = lib.mkIf (pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64) {
      XDG_BACKEND = "wayland";
      XDG_RUNTIME_DIR = "/run/user/$(id -u)";

      # XDG_VTNR = "1";

      # TODO: move to xdg
      # XDG_SESSION_CLASS = "user";
      # XDG_CACHE_HOME = config.xdg.cacheHome;
      # XDG_CONFIG_HOME = config.xdg.configHome;
      # XDG_DATA_HOME = config.xdg.dataHome;
      # XDG_STATE_HOME = config.xdg.stateHome;

      # XDG_DESKTOP_DIR = config.xdg.userDirs.desktop;
      # XDG_DOCUMENTS_DIR = config.xdg.userDirs.documents;
      # XDG_DOWNLOAD_DIR = config.xdg.userDirs.download;
      # XDG_MUSIC_DIR = config.xdg.userDirs.music;
      # XDG_PICTURES_DIR = config.xdg.userDirs.pictures;
      # XDG_PUBLICSHARE_DIR = config.xdg.userDirs.publicShare;
      # XDG_TEMPLATES_DIR = config.xdg.userDirs.templates;
      # XDG_VIDEOS_DIR = config.xdg.userDirs.videos;

      # Additional XDG-related variables
      # PARALLEL_HOME = "${config.xdg.configHome}/parallel";
      # SCREENRC = "${config.xdg.configHome}/screen/screenrc";
    };

    sessionPath = lib.mkIf pkgs.stdenv.isDarwin [
      "/usr/local/bin"
      "/etc/profiles/per-user/$USER/bin"
      "/nix/var/nix/profiles/system/sw/bin"
    ];
  };
}
