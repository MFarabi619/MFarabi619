{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    shellAliases = {
      cat = "bat";
      man = "batman";
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
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ../../..;
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

    envExtra = ''
      # Custom ~/.zshenv goes here
    '';
    profileExtra = ''
      # Custom ~/.zprofile goes here
    '';
    loginExtra = ''
      # Custom ~/.zlogin goes here
    '';
    logoutExtra = ''
      # Custom ~/.zlogout goes here
    '';
  };
}
