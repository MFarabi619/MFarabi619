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
    # base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-macchiato.yaml";

    targets = {
      vscode.enable = false;
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
      desktop = 0.9;
      terminal = 0.9;
      applications = 0.9;
    };

    fonts = {
      sizes = {
        popups = 12;
        desktop = 12;
        terminal = 14;
        applications = 14;
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
