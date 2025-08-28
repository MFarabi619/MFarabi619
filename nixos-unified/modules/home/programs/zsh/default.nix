{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    autocd = false;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
      # highlight = "fg=#ff00ff,bg=cyan,bold,underline";
    };

    shellAliases = {
      cat = "bat";
      man = "batman";
      lg = "lazygit";
      enw = "emacs -nw";
      z = "zoxide";
      zlj = "zellij";
      mkdir = "mkdir -p";
    };

    syntaxHighlighting = {
      enable = true;
      highlighters = [
        "main"
        "brackets"
        "pattern"
        "regexp"
        "root"
        "line"
      ];
    };

    history = {
      size = 10000;
      save = 10000;
      share = true;
      append = true;
      extended = true;
      ignoreDups = true;
      ignoreAllDups = true;
      expireDuplicatesFirst = true;
      # path = "`\${config.programs.zsh.dotDir}/.zsh_history`"; # default
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./.;
        file = ".p10k.zsh";
      }
    ];
    oh-my-zsh = {
      enable = true;
      plugins = [
        "sudo"
        "git"
        "colored-man-pages"
        "colorize"
        "docker"
        "docker-compose"
        "kubectl"
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "dash"
        "macos"
      ];
    };

    # envExtra = ''
    #   # Custom ~/.zshenv goes here
    # '';
    # profileExtra = ''
    #   # Custom ~/.zprofile goes here
    # '';
    # loginExtra = ''
    #   # Custom ~/.zlogin goes here
    # '';
    # logoutExtra = ''
    #   # Custom ~/.zlogout goes here
    # '';
  };
}
