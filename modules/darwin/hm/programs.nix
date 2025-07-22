{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.lazyvim.homeManagerModules.default
  ];

  programs = {
    # vivaldi.enable = true;
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
    fastfetch = {
      enable = true;
      settings = {
      };
    };
    zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      initContent = lib.mkBefore ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

        [[ -f ~/.p10k.zsh ]] && source ~/MFarabi619/configurations/home/.p10k.zsh
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
  };
}
