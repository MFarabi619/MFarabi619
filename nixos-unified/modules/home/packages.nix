{
  pkgs,
  lib,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # clang
      # =============
      cmake # vterm compilation and more
      coreutils
      binutils # native-comp needs 'as', provided by this
      gnutls # for TLS connectivity
      # =============
      openscad
      openscad-lsp
      # =============
      vips # dired image previews
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      imagemagick # for image-dired
      # =============
      octaveFull # gnu octave
      mermaid-cli # mermaid diagram support
      # =============
      tuntox # collab
      # =============
      sqlite # :tools lookup & :lang org +roam
      # =============
      ispell # spelling
      # =============
      shellcheck # shell script formatting
      # =============
      # texlive     # :lang latex & :lang org (latex previews)
      # vimPlugins.nvim-treesitter-parsers.mermaid
      # ============= 🧑‍💻🐞✨‍ ================
      # pnpm
      tgpt
      pik
      wiki-tui
      gpg-tui
      termscp
      bandwhich
      cointop # crypto price feed
      nix-inspect

      tree
      gnumake

      # ============= ‍❄🕸 ================
      nil # nix formatter
      nix-info
      nix-inspect
      nixpkgs-fmt
      nix-health
      omnix
      devenv

      # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
      # work.
      less

      # Setup Claude Code using Google Vertex AI Platform
      # https://github.com/juspay/vertex
      # flake.inputs.vertex.packages.${system}.default

      # ============== 🤪 =================
      asciiquarium # ascii aquarium
      cowsay
      cmatrix
      figlet # fancy ascii text output
      nyancat # rainbow flying cat
      lolcat # rainbow text output
    ]
    ++ lib.optionals stdenv.isLinux [
      # ============= 🧑‍💻🐞✨‍ ================
      kmon
      lazyjournal
      systemctl-tui
      netscanner
      ugm # user group management
      isd # systemd units
      dysk # see mounted

      virt-viewer

      # ============== 🤪 =================
      hollywood
    ]
    ++ lib.optionals stdenv.isDarwin [
      sketchybar-app-font
      sbarlua
      alt-tab-macos
    ];
}
