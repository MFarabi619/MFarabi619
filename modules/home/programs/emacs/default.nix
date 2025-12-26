{
  pkgs,
  ...
}:
{
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    # provideEmacs = false;
    # experimentalFetchTree = true;

    extraPackages =
      epkgs:
      let
        treesitWithAllExceptRazor = epkgs.treesit-grammars.with-grammars (
          grammars:
          builtins.attrValues (
            builtins.removeAttrs grammars [
              "tree-sitter-razor"
              "tree-sitter-razor-grammar"
            ]
          )
        );
      in
      with epkgs;
      [
        pg
        nov
        mu4e
        verb
        gptel # ai
        vterm # terminal emulation
        circe
        corfu
        org-anki
        pdf-tools
        org-roam-ui
        corfu-terminal
        nerd-icons-corfu

        devdocs
        devdocs-browser
        compiler-explorer

        wttrin
        shrface
        keycast
        kdl-mode
        leetcode
        exercism
        nix-update
        nix-ts-mode
        all-the-icons

        lsp-tailwindcss
        treesitWithAllExceptRazor
        # ================
        abc-mode
        scad-mode
        ob-mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
        org-table-highlight
        # ================
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        org-super-agenda
        # ================
        # jira
        # obsidian
        # platformio-mode
        # catppuccin-theme
      ];

    extraBinPackages =
      with pkgs;
      [
        buf # protobuf lsp
        protobuf
        protoc-gen-go
        protoc-gen-go-grpc

        jq # :lang rest
        jq-lsp
        graphql-language-service-cli

        asmfmt
        asm-lsp

        nix
        nil # nix language server
        nixfmt # nix formatter

        cargo
        rust-analyzer

        zig
        zls

        nodejs_25

        go
        gore
        gopls
        gotests
        gomodifytags
        gocode-gomod
        golangci-lint

        ruby-lsp

        ruff
        isort
        pyright

        pandoc
        gnuplot
        graphviz
        plantuml
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support

        fd
        git
        unzip
        gnutar
        ispell
        tuntox # collab
        # semgrep
        ripgrep
        openscad
        rustywind
        openscad-lsp

        shfmt
        shellcheck # shell script formatting
        bash-language-server

        figlet # needed for artist-mode
        eslint
        proselint
        markdownlint-cli
        mdx-language-server

        taplo # toml lsp
        emmet-ls
        yaml-language-server
        dockerfile-language-server
        vscode-langservers-extracted

        vips # dired image previews
        poppler # dired pdf previews
        mediainfo
        imagemagick # for image-dired
        coreutils-full
        epub-thumbnailer # dired epub previews
        ffmpegthumbnailer

        sqls
        duckdb
        sqlite # :tools lookup & :lang org +roam
        postgres-language-server

        gnutls # :app irc
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
        bashdb
      ];
  };

  services.emacs = {
    enable = true;
    defaultEditor = false;
    socketActivation.enable = true;

    # extraOptions = [
    #   "TERM=xterm-kitty"
    # ];

    client = {
      enable = true;
      # arguments = [
      #   "--tty"
      # ];
    };
  };
}
