{
  lib,
  pkgs,
  flake,
  config,
  ...
}:
{
  imports = [
    flake.inputs.nix-doom-emacs-unstraightened.homeModule
  ];

  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    # provideEmacs = false;
    experimentalFetchTree = config.targets.genericLinux.enable;

    extraPackages =
      epkgs:
      let
        treesitWithAllExceptQuint = epkgs.treesit-grammars.with-grammars (
          grammars:
          builtins.attrValues (
            builtins.removeAttrs grammars [
              "tree-sitter-quint"
            ]
          )
        );
      in
      with epkgs;
      [
        nov
        mu4e
        empv
        verb
        # gptel
        vterm
        circe
        corfu
        prodigy
        pdf-tools
        magit-delta
        corfu-terminal
        nerd-icons-corfu

        sqlup-mode

        devdocs
        devdocs-browser
        compiler-explorer

        multi-vterm
        compile-multi
        fancy-compilation
        compile-multi-embark
        consult-compile-multi

        kconfig-ref
        kconfig-mode

        osm
        org-anki
        org-roam-ui
        org-pdftools
        org-nix-shell
        org-super-agenda
        org-tag-beautify
        org-link-beautify
        org-table-highlight

        wttrin
        shrface
        keycast
        kdl-mode
        leetcode
        exercism
        nix-update
        nixos-options
        all-the-icons

        lsp-tailwindcss
        treesitWithAllExceptQuint
        # treesit-grammars.with-all-grammars
        # ================
        abc-mode
        scad-mode
        ob-mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
        # ================
        parrot
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        # ================
        # jira
        # obsidian
        # platformio-mode
        # catppuccin-theme
      ]
      ++ lib.optionals (pkgs.stdenv.isDarwin) [
        consult-spotlight
      ];

    extraBinPackages =
      with pkgs;
      [
        nil
        nixfmt
        ispell

        buf # protobuf lsp
        protobuf
        protoc-gen-go
        protoc-gen-go-grpc

        jq-lsp
        graphql-language-service-cli

        # ===== 🛠 ASSEMBLY 🛠 ======
        asmfmt

        # ===== 🦫 GO 🦫 ======
        gore
        gotests
        gomodifytags
        gocode-gomod
        golangci-lint

        # ==== 🚂 RUBY 🚂 =====
        ruby-lsp

        graphviz
        plantuml
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support

        fd
        git
        tuntox # collab
        gnutls # :app irc
        # semgrep

        # eslint
        # proselint
        rustywind
        # markdownlint-cli
        # mdx-language-server

        lldb
        taplo # toml lsp
        # emmet-ls
        # yaml-language-server
        # dockerfile-language-server
        # vscode-langservers-extracted
        vscode-extensions.llvm-vs-code-extensions.lldb-dap

        # ==== 💿 SQL 💿 =====
        postgres-language-server
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
        bashdb
      ];
  };

  services.emacs = {
    enable = true;
    defaultEditor = false;
    # socketActivation.enable = true;

    # extraOptions = [
    #   "TERM=xterm-kitty"
    # ];

    # client = {
    #   enable = true;
    #   # arguments = [
    #   #   "--tty"
    #   # ];
    # };
  };
}
