{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    autocd = false;
    enableCompletion = true;
    shellAliases.mkdir = "mkdir -p";

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


    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };

    syntaxHighlighting = {
      enable = true;
      highlighters = [
        "line"
        "main"
        "root"
        "regexp"
        "pattern"
        "brackets"
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
        src = lib.cleanSource ./.;
        file = ".p10k.zsh";
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "colorize"
        "docker-compose"
        "colored-man-pages"
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "dash"
        "macos"
      ];
    };

    # envExtra = '''';     # ~/.zshenv
    # loginExtra = '''';   # ~/.zlogin
    # logoutExtra = '''';  # ~/.zlogout
    # profileExtra = ''''; # ~/.zprofile
  };
}
