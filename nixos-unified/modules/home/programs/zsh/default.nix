{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
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

    # history = {
    #   ignoreDups = true;
    #   save = 10000;
    #   size = 10000;
    # };

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
