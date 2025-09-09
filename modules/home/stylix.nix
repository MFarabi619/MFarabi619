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
      vim.enable = true;
      fontconfig.enable = true;
      font-packages.enable = true;

      neovim = {
        enable = false;
        transparentBackground = {
          main = true;
          numberLine = true;
          signColumn = true;
        };
      };

      kitty = {
        enable = true;
        variant256Colors = false;
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
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };

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
    };
  };
}
