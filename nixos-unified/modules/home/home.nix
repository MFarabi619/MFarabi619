{
  pkgs,
  lib,
  ...
}:
{
  home = {
    shell = {
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    packages =
      with pkgs;
      [
        noto-fonts

        # ==========  Doom Emacs ===========
        # clang
        cmake # vterm compilation and more
        coreutils
        binutils # native-comp needs 'as', provided by this
        gnutls # for TLS connectivity
        epub-thumbnailer # dired epub previews
        poppler-utils # dired pdf previews
        openscad
        openscad-lsp
        vips # dired image previews
        imagemagick # for image-dired
        tuntox # collab
        sqlite # :tools lookup & :lang org +roam
        ispell # spelling
        shellcheck # shell script formatting
        # texlive     # :lang latex & :lang org (latex previews)

        # ============= 🧑‍💻🐞‍ ================
        # pnpm
        tgpt
        pik
        wiki-tui
        gpg-tui
        termscp
        bandwhich

        omnix

        tree
        gnumake

        devenv
        cachix
        nil
        nix-info
        nix-inspect
        nixpkgs-fmt
        nix-health

        # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
        # work.
        less

        # Setup Claude Code using Google Vertex AI Platform
        # https://github.com/juspay/vertex
        # flake.inputs.vertex.packages.${system}.default

        # ============== 🤪 =================
        asciiquarium
        cowsay
        cmatrix
        figlet
        nyancat
        lolcat
        cointop
      ]
      ++ lib.optionals stdenv.isLinux [
        ugm
        isd # systemd units TUI
        dysk # see mounted disks

        wl-clipboard

        netscanner

        kmon
        lazyjournal
        systemctl-tui
        virt-viewer

        hollywood
      ]
      ++ lib.optionals stdenv.isDarwin [
        sketchybar-app-font
        sbarlua
        alt-tab-macos
      ];

    sessionVariables = lib.mkIf pkgs.stdenv.isLinux {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";

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
