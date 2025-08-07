{ pkgs, lib, ... }:
{
  programs = {
    # on macOS, you probably don't need this
    bash = {
      enable = true;
      initExtra = ''
        # Custom bash profile goes here
      '';
    };

    # macOS's default shell.
    zsh = {
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
          src = lib.cleanSource ../..;
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

    # starship = {
    #   enable = true;
    #   settings = {
    #     username = {
    #       style_user = "blue bold";
    #       style_root = "red bold";
    #       format = "[$user]($style) ";
    #       disabled = false;
    #       show_always = true;
    #     };
    #     hostname = {
    #       ssh_only = false;
    #       ssh_symbol = "🌐 ";
    #       format = "on [$hostname](bold red) ";
    #       trim_at = ".local";
    #       disabled = false;
    #     };
    #   };
    # };
  };
}
