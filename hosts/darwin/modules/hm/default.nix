{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    inputs.lazyvim.homeManagerModules.default
    inputs.nix-doom-emacs-unstraightened.homeModule
    ../../../../modules/hm/doom-emacs.nix
    ../../../../modules/hm/git.nix
    ../../../../modules/hm/lazygit.nix
    ../../../../modules/hm/gh.nix
    ../../../../modules/hm/yazi.nix
    ../../../../modules/hm/stylix.nix
    ../../../../modules/hm/manual.nix
    ../../../../modules/hm/home.nix
    ../../../../modules/hm/editorconfig.nix
    ../../../../modules/hm/services.nix
    ./darwin.nix
    ../../../../modules/hm/aerospace.nix
  ];

  programs = {
    home-manager.enable = true;
    sketchybar = {
      enable = true;
      service.enable = true;
      includeSystemPath = true;
      config = {
        source = ../../../../modules/hm/sketchybar;
        recursive = true;
      };
    };
    go = {
      enable = true;
    };
    jq = {
      enable = true;
    };
    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    kitty = {
      enable = true;
      shellIntegration = {
        enableBashIntegration = true;
        enableZshIntegration = true;
      };
      enableGitIntegration = true;
    };
    neovim = {
      enable = true;
      defaultEditor = true;
    };
    lazysql.enable = true;
    lazyvim = {
      enable = true;
      plugins = with pkgs; [
        vimPlugins.base16-nvim
      ];
      extras = {
        util = {
          dot.enable = true;
        };
        ui = {
          mini-animate.enable = true;
        };
        editor = {
          fzf.enable = true;
          # neotree.enable = true;
        };
        test.core.enable = true;
        lang = {
          nix.enable = true;
          json.enable = true;
          # markdown.enable = true;
          tailwind.enable = true;
          typescript.enable = true;
          python.enable = true;
        };
        dap.core.enable = true;
      };
    };
    bat.enable = true;
    fastfetch = {
      enable = true;
      settings = {
      };
    };
    eza = {
      enable = true;
      icons = "auto";
      colors = "auto";
      git = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--group-directories-first"
      ];
    };
    nix-index = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      initContent = lib.mkBefore ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

        [[ -f ~/.p10k.zsh ]] && source ~/MFarabi619/libs/dotfiles/hosts/darwin/modules/hm/.p10k.zsh
      '';
      oh-my-zsh = {
        enable = true;
        plugins =
          [
            "sudo"
            "git"
            "colored-man-pages"
            "colorize"
            "docker"
            "docker-compose"
            "git"
            "kubectl"
          ]
          ++ lib.optionals pkgs.stdenv.isDarwin [
            "dash"
            "macos"
          ];
      };

      shellAliases = {
        cat = "bat";
      };
    };
    bun.enable = true;
    btop.enable = true;
    lazydocker.enable = true;
    direnv = {
      enable = true;
      silent = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    fd.enable = true;
    ripgrep.enable = true;
    pandoc.enable = true;
    texlive.enable = true;
    tex-fmt.enable = true;
    nh.enable = true;
    k9s.enable = true;
    kubecolor = {
      enable = true;
      enableAlias = true;
    };
    zellij = {
      enable = true;
      settings = {
      };
      # enableZshIntegration = true;
      # attachExistingSession = true;
    };
  };
}
