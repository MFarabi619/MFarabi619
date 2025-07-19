{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  programs = {
    stylix = {
      enable = true;
      autoEnable = true;
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

      #    iconTheme = {
      #      enable = true;
      #    };

      opacity = {
        applications = 0.8;
        terminal = 0.8;
      };

      fonts = {
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

      base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";
    };
  };
}
