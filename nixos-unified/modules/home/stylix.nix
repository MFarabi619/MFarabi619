{
  pkgs,
  ...
}:
{
  stylix = {
    enable = true;
    autoEnable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    targets = {
      fontconfig.enable = true;
      font-packages.enable = true;
      vim.enable = true;
      neovim = {
        enable = false;
        transparentBackground = {
          main = true;
          numberLine = true;
          signColumn = true;
        };
      };
      bat.enable = true;
      fzf.enable = true;
      kitty = {
        enable = true;
        variant256Colors = false;
      };
      lazygit.enable = true;
      zellij.enable = true;
    };

    icons = {
      enable = true;
    };

    #    iconTheme = {
    #      enable = true;
    #    };

    opacity = {
      applications = 0.9;
      terminal = 0.9;
      desktop = 1.0;
    };

    fonts = {
      packages =
        with pkgs;
        [
          noto-fonts-emoji
          noto-fonts-cjk-sans
          font-awesome
          symbola
          material-icons
          fira-code
          fira-code-symbols
          nerd-fonts.jetbrains-mono
        ]
        ++ lib.optionals stdenv.isDarwin [
          sketchybar-app-font
        ];

      serif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };

      sansSerif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };

      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };

      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };

  };
}
