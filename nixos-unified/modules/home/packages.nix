{ flake, pkgs, ... }:
{
  imports = [
    ./programs
  ];

  home.packages = with pkgs; [
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
    nil # nix lang formatting
    shellcheck # shell script formatting
    # texlive     # :lang latex & :lang org (latex previews)
    #
    omnix

    tree
    gnumake

    # Nix dev
    cachix
    nil # Nix language server
    nix-info
    nixpkgs-fmt

    # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
    # work.
    less

    # Setup Claude Code using Google Vertex AI Platform
    # https://github.com/juspay/vertex
    flake.inputs.vertex.packages.${system}.default
  ];

  # Programs natively supported by home-manager.
  # They can be configured in `programs.*` instead of using home.packages.
  programs = {
    tmate = {
      enable = true;
      #host = ""; #In case you wish to use a server other than tmate.io
    };
  };

services = {
    cachix-agent = {
      name = "nixos-msi-gs65";
      enable = true;
      verbose = true;
    };
};
}
