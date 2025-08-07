{ pkgs, ... }:
{
  home = {
    shell = {
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    packages = with pkgs; [
      tree
      gnumake

      devenv

      # ==========  Doom Emacs ===========
      # clang
      cmake # vterm compilation and more
      coreutils
      binutils # native-comp needs 'as', provided by this
      gnutls # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      openscad
      openscad-lsp
      vips # dired image previews
      imagemagick # for image-dired
      tuntox # collab
      sqlite # :tools lookup & :lang org +roam
      ispell # spelling
      shellcheck # shell script formatting
      # texlive     # :lang latex & :lang org (latex previews)

      rofi-wayland
      wl-clipboard
      noto-fonts

      omnix

      tree
      gnumake

      cachix
      nil
      nix-info
      nix-inspect
      nix-search-tv
      nixpkgs-fmt
      nix-health

      # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
      # work.
      less

      # Setup Claude Code using Google Vertex AI Platform
      # https://github.com/juspay/vertex
      # flake.inputs.vertex.packages.${system}.default
    ];

    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
