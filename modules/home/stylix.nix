{
  pkgs,
  ...
}:
{
  stylix = {
    enable = true;
    autoEnable = true;
    polarity = "dark";
    # base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-macchiato.yaml";

    targets = {
      vim.enable = true;
      fontconfig.enable = true;
      font-packages.enable = true;

      neovim = {
        enable = true;
        transparentBackground = {
          main = true;
          numberLine = true;
          signColumn = true;
        };
      };

      kitty = {
        enable = true;
        variant256Colors = true;
      };
    };

    icons = {
      enable = true;
      dark = "dark";
      light = "light";
      package = pkgs.nerd-fonts.symbols-only;
    };

    opacity = {
      popups = 0.9;
      desktop = 1.0;
      terminal = 0.9;
      applications = 0.9;
    };

    fonts = {
      sizes = {
        # terminal = 12;
      };

      emoji = {
        name = "Noto Color Emoji";
        package = pkgs.noto-fonts-color-emoji;
      };

      serif = {
        name = "JetBrainsMono Nerd Font";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };

      sansSerif = {
        name = "JetBrainsMono Nerd Font";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };

      monospace = {
        name = "JetBrainsMono Nerd Font";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };
    };
  };
}
