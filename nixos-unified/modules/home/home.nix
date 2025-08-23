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
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    sessionVariables = lib.mkIf pkgs.stdenv.isLinux {
      XDG_RUNTIME_DIR = "/run/user/$(id -u)";

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
      LESSHISTFILE = "/tmp/less-hist";
      # PARALLEL_HOME = "${config.xdg.configHome}/parallel";
      # SCREENRC = "${config.xdg.configHome}/screen/screenrc";
      ZSH_AUTOSUGGEST_STRATEGY = "history completion";

      # History configuration // explicit to not nuke history
      HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
      HISTSIZE = "10000";
      SAVEHIST = "10000";
      setopt_EXTENDED_HISTORY = "true";
      setopt_INC_APPEND_HISTORY = "true";
      setopt_SHARE_HISTORY = "true";
      setopt_HIST_EXPIRE_DUPS_FIRST = "true";
      setopt_HIST_IGNORE_DUPS = "true";
      setopt_HIST_IGNORE_ALL_DUPS = "true";
    };

    sessionPath = lib.mkIf pkgs.stdenv.isDarwin [
      "/etc/profiles/per-user/$USER/bin"
      "/nix/var/nix/profiles/system/sw/bin"
      "/usr/local/bin"
    ];
  };
}
