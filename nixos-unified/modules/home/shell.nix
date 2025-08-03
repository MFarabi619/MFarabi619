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
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      shellAliases = {
        cat = "bat";
      };
      initContent = lib.mkBefore ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

        [[ -f ~/.p10k.zsh ]] && source ~/MFarabi619/nixos-unified/.p10k.zsh
      '';
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

    # Type `z <pat>` to cd to some directory
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      # options = [

      # ];
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
